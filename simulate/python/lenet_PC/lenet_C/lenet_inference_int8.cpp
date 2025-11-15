// LeNet INT8 inference (true int8×int8→int32 compute) with per-layer error analysis vs FP32
// Build: cl /O2 /std:c++17 lenet_inference_int8.cpp
#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iomanip>
#include <numeric>
#include <string>
#include <vector>
#include <chrono>

using namespace std;
using hrc = chrono::high_resolution_clock;
using dur_us = chrono::duration<double, micro>;

// ===== NPY reader (float32) =====
static bool load_npy_float32(const string& path, vector<int64_t>& shape, vector<float>& data) {
    ifstream f(path, ios::binary);
    if (!f) { cerr << "Cannot open: " << path << "\n"; return false; }
    char magic[6]; f.read(magic, 6);
    if (string(magic, 6) != "\x93NUMPY") { cerr << "Bad npy magic\n"; return false; }
    unsigned char ver[2]; f.read(reinterpret_cast<char*>(ver), 2);
    uint16_t hlen=0;
    if (ver[0]==1 && ver[1]==0) { uint16_t h; f.read(reinterpret_cast<char*>(&h),2); hlen=h; }
    else if (ver[0]==2 && ver[1]==0) { uint32_t h; f.read(reinterpret_cast<char*>(&h),4); hlen=uint16_t(h); }
    else { uint32_t h; f.read(reinterpret_cast<char*>(&h),4); hlen=uint16_t(h); }
    string header(hlen,' '); f.read(header.data(), hlen);
    if (header.find("'descr': '<f4'")==string::npos && header.find("\"descr\": \"<f4\"")==string::npos) {
        cerr << "Only support little-endian float32\n"; return false;
    }
    auto p0 = header.find('('), p1 = header.find(')', p0+1);
    if (p0==string::npos||p1==string::npos) { cerr << "Bad shape\n"; return false; }
    string shp = header.substr(p0+1, p1-p0-1);
    shape.clear(); size_t start=0;
    while (start<shp.size()){
        auto comma = shp.find(',', start);
        string tok = shp.substr(start, (comma==string::npos?shp.size():comma)-start);
        tok.erase(remove_if(tok.begin(),tok.end(),::isspace), tok.end());
        if (!tok.empty()) shape.push_back(stoll(tok));
        if (comma==string::npos) break;
        start = comma+1;
    }
    size_t cnt=1; for (auto d: shape) cnt *= size_t(d);
    data.resize(cnt); f.read(reinterpret_cast<char*>(data.data()), cnt*sizeof(float));
    return true;
}

// ===== Read MNIST idx =====
static bool read_mnist_images(const string& path, vector<vector<float>>& imgs28) {
    ifstream f(path, ios::binary);
    if (!f) { cerr << "Cannot open images: " << path << "\n"; return false; }
    auto r32 = [&](int32_t& x) {
        f.read(reinterpret_cast<char*>(&x), 4);
        x = ((x&0xff000000)>>24)|((x&0x00ff0000)>>8)|((x&0x0000ff00)<<8)|((x&0x000000ff)<<24);
    };
    int32_t magic=0, num=0, rows=0, cols=0;
    r32(magic); r32(num); r32(rows); r32(cols);
    if (magic!=2051||rows!=28||cols!=28) { cerr << "Bad image idx\n"; return false; }
    imgs28.assign(num, vector<float>(rows*cols));
    for (int i=0;i<num;++i){
        for (int j=0;j<rows*cols;++j){
            unsigned char pix=0; f.read(reinterpret_cast<char*>(&pix),1);
            imgs28[i][j] = float(pix)/255.0f;
        }
    }
    return true;
}

static bool read_mnist_labels(const string& path, vector<int>& labels) {
    ifstream f(path, ios::binary);
    if (!f) { cerr << "Cannot open labels: " << path << "\n"; return false; }
    auto r32 = [&](int32_t& x) {
        f.read(reinterpret_cast<char*>(&x), 4);
        x = ((x&0xff000000)>>24)|((x&0x00ff0000)>>8)|((x&0x0000ff00)<<8)|((x&0x000000ff)<<24);
    };
    int32_t magic=0, num=0; r32(magic); r32(num);
    if (magic!=2049) { cerr << "Bad label idx\n"; return false; }
    labels.resize(num);
    for (int i=0;i<num;++i){
        unsigned char lab=0; f.read(reinterpret_cast<char*>(&lab),1);
        labels[i] = int(lab);
    }
    return true;
}

static inline int clamp(int v, int lo, int hi) { return min(max(v,lo),hi); }

static vector<float> resize_bilinear(const vector<float>& src, int Hs, int Ws, int Hd=32, int Wd=32) {
    vector<float> dst(Hd*Wd);
    float sy_scale = float(Hs)/Hd, sx_scale = float(Ws)/Wd;
    for (int y=0;y<Hd;++y){
        float sy = (y+0.5f)*sy_scale - 0.5f;
        int y0 = int(floor(sy)), y1 = y0+1;
        float wy1 = sy - y0, wy0 = 1.0f - wy1;
        y0 = clamp(y0, 0, Hs-1); y1 = clamp(y1, 0, Hs-1);
        for (int x=0;x<Wd;++x){
            float sx = (x+0.5f)*sx_scale - 0.5f;
            int x0 = int(floor(sx)), x1 = x0+1;
            float wx1 = sx - x0, wx0 = 1.0f - wx1;
            x0 = clamp(x0, 0, Ws-1); x1 = clamp(x1, 0, Ws-1);
            float v00=src[y0*Ws+x0], v01=src[y0*Ws+x1], v10=src[y1*Ws+x0], v11=src[y1*Ws+x1];
            float v0 = v00*wx0 + v01*wx1;
            float v1 = v10*wx0 + v11*wx1;
            dst[y*Wd + x] = v0*wy0 + v1*wy1;
        }
    }
    return dst;
}

// ===== Quantization helpers =====
static inline int8_t quantize_int8(float x, float scale) {
    if (scale<=0) return 0;
    int q = int(round(x/scale));
    return int8_t(clamp(q, -128, 127));
}

static inline float dequantize(int32_t q, float scale) {
    return float(q) * scale;
}

static float max_abs(const vector<float>& x){
    float m=0.0f; for (auto v: x) m = max(m, fabs(v)); return m;
}

static void get_weight_scales_conv(const vector<float>& w, int OC, int IC, int KH, int KW, vector<float>& scales){
    scales.assign(OC, 1.0f);
    int perOC = IC*KH*KW;
    for (int oc=0; oc<OC; ++oc){
        float m=0.0f; const float* p = w.data() + oc*perOC;
        for (int i=0;i<perOC;++i) m = max(m, fabs(p[i]));
        scales[oc] = (m>0.0f ? m/127.0f : 1.0f);
    }
}

static void get_weight_scales_fc(const vector<float>& w, int OC, int IC, vector<float>& scales){
    scales.assign(OC, 1.0f);
    for (int oc=0; oc<OC; ++oc){
        float m=0.0f; const float* row = w.data() + oc*IC;
        for (int i=0;i<IC;++i) m = max(m, fabs(row[i]));
        scales[oc] = (m>0.0f ? m/127.0f : 1.0f);
    }
}

// ===== FP32 reference ops =====
static inline float relu_fp(float x) { return x>0?x:0; }

static vector<float> conv2d_fp32(const vector<float>& x, int Cin, int Hin, int Win,
                                  const vector<float>& w, const vector<float>& b,
                                  int Cout, int K) {
    int Hout = Hin - K + 1, Wout = Win - K + 1;
    vector<float> y(Cout*Hout*Wout, 0.0f);
    for (int oc=0;oc<Cout;++oc){
        for (int oh=0;oh<Hout;++oh){
            for (int ow=0;ow<Wout;++ow){
                float acc = b[oc];
                for (int ic=0;ic<Cin;++ic){
                    for (int kh=0;kh<K;++kh){
                        for (int kw=0;kw<K;++kw){
                            acc += x[ic*Hin*Win + (oh+kh)*Win + (ow+kw)] * w[oc*Cin*K*K + ic*K*K + kh*K + kw];
                        }
                    }
                }
                y[oc*Hout*Wout + oh*Wout + ow] = acc;
            }
        }
    }
    return y;
}

static void relu_fp32_inplace(vector<float>& x){ for (auto& v: x) v = relu_fp(v); }

static vector<float> maxpool2x2s2_fp32(const vector<float>& x, int C, int H, int W) {
    int Hout = H/2, Wout = W/2;
    vector<float> y(C*Hout*Wout);
    for (int c=0;c<C;++c){
        for (int oh=0;oh<Hout;++oh){
            for (int ow=0;ow<Wout;++ow){
                float m = -1e30f;
                for (int kh=0;kh<2;++kh){
                    for (int kw=0;kw<2;++kw){
                        m = max(m, x[c*H*W + (oh*2+kh)*W + (ow*2+kw)]);
                    }
                }
                y[c*Hout*Wout + oh*Wout + ow] = m;
            }
        }
    }
    return y;
}

static vector<float> fc_fp32(const vector<float>& x, const vector<float>& w, const vector<float>& b, int In, int Out) {
    vector<float> out(Out);
    for (int o=0;o<Out;++o){
        float acc = b[o];
        const float* row = w.data() + o*In;
        for (int i=0;i<In;++i) acc += row[i]*x[i];
        out[o] = acc;
    }
    return out;
}

// ===== INT8 ops =====
static vector<int8_t> quantize_tensor_int8(const vector<float>& x, float scale) {
    vector<int8_t> q(x.size());
    for (size_t i=0;i<x.size();++i) q[i] = quantize_int8(x[i], scale);
    return q;
}

static vector<int8_t> quantize_weight_per_channel_conv(const vector<float>& w, const vector<float>& scales, int OC, int IC, int KH, int KW) {
    int perOC = IC*KH*KW;
    vector<int8_t> q(w.size());
    for (int oc=0; oc<OC; ++oc){
        float s = scales[oc];
        for (int i=0; i<perOC; ++i){
            q[oc*perOC + i] = quantize_int8(w[oc*perOC + i], s);
        }
    }
    return q;
}

static vector<int8_t> quantize_weight_per_channel_fc(const vector<float>& w, const vector<float>& scales, int OC, int IC) {
    vector<int8_t> q(w.size());
    for (int oc=0; oc<OC; ++oc){
        float s = scales[oc];
        for (int i=0; i<IC; ++i){
            q[oc*IC + i] = quantize_int8(w[oc*IC + i], s);
        }
    }
    return q;
}

// Conv2d INT8: int8×int8→int32, then dequantize with combined scale
static vector<float> conv2d_int8(const vector<int8_t>& x_q, float x_scale, int Cin, int Hin, int Win,
                                  const vector<int8_t>& w_q, const vector<float>& w_scales,
                                  const vector<float>& b, int Cout, int K) {
    int Hout = Hin - K + 1, Wout = Win - K + 1;
    vector<float> y(Cout*Hout*Wout);
    for (int oc=0;oc<Cout;++oc){
        float scale_out = x_scale * w_scales[oc];
        for (int oh=0;oh<Hout;++oh){
            for (int ow=0;ow<Wout;++ow){
                int32_t acc = 0;
                for (int ic=0;ic<Cin;++ic){
                    for (int kh=0;kh<K;++kh){
                        for (int kw=0;kw<K;++kw){
                            int8_t xv = x_q[ic*Hin*Win + (oh+kh)*Win + (ow+kw)];
                            int8_t wv = w_q[oc*Cin*K*K + ic*K*K + kh*K + kw];
                            acc += int32_t(xv) * int32_t(wv);
                        }
                    }
                }
                y[oc*Hout*Wout + oh*Wout + ow] = dequantize(acc, scale_out) + b[oc];
            }
        }
    }
    return y;
}

// ReLU INT8 (quantize input, clamp negative to 0, dequantize)
static vector<float> relu_int8(const vector<float>& x, float scale) {
    vector<int8_t> q = quantize_tensor_int8(x, scale);
    for (auto& v: q) if (v<0) v=0;
    vector<float> y(q.size());
    for (size_t i=0;i<q.size();++i) y[i] = dequantize(q[i], scale);
    return y;
}

// MaxPool INT8 (quantize, do maxpool in int8, dequantize)
static vector<float> maxpool2x2s2_int8(const vector<float>& x, float scale, int C, int H, int W) {
    vector<int8_t> xq = quantize_tensor_int8(x, scale);
    int Hout = H/2, Wout = W/2;
    vector<int8_t> yq(C*Hout*Wout);
    for (int c=0;c<C;++c){
        for (int oh=0;oh<Hout;++oh){
            for (int ow=0;ow<Wout;++ow){
                int8_t m = -128;
                for (int kh=0;kh<2;++kh){
                    for (int kw=0;kw<2;++kw){
                        m = max(m, xq[c*H*W + (oh*2+kh)*W + (ow*2+kw)]);
                    }
                }
                yq[c*Hout*Wout + oh*Wout + ow] = m;
            }
        }
    }
    vector<float> y(yq.size());
    for (size_t i=0;i<yq.size();++i) y[i] = dequantize(yq[i], scale);
    return y;
}

// FC INT8
static vector<float> fc_int8(const vector<float>& x, float x_scale, const vector<int8_t>& w_q, const vector<float>& w_scales, const vector<float>& b, int In, int Out) {
    vector<int8_t> xq = quantize_tensor_int8(x, x_scale);
    vector<float> out(Out);
    for (int o=0;o<Out;++o){
        int32_t acc = 0;
        const int8_t* row = w_q.data() + o*In;
        for (int i=0;i<In;++i) acc += int32_t(xq[i]) * int32_t(row[i]);
        out[o] = dequantize(acc, x_scale * w_scales[o]) + b[o];
    }
    return out;
}

static int argmax(const vector<float>& x){
    return int(max_element(x.begin(), x.end()) - x.begin());
}

// ===== Error metrics =====
struct ErrorMetrics {
    double l1=0, l2=0, cosine=1.0;
    void compute(const vector<float>& ref, const vector<float>& test) {
        assert(ref.size() == test.size());
        double sum_abs=0, sum_sq=0, dot=0, norm_ref=0, norm_test=0;
        for (size_t i=0;i<ref.size();++i){
            double diff = test[i] - ref[i];
            sum_abs += fabs(diff);
            sum_sq += diff*diff;
            dot += ref[i]*test[i];
            norm_ref += ref[i]*ref[i];
            norm_test += test[i]*test[i];
        }
        l1 = sum_abs / ref.size();
        l2 = sqrt(sum_sq / ref.size());
        cosine = (norm_ref>0 && norm_test>0) ? dot/(sqrt(norm_ref)*sqrt(norm_test)) : 1.0;
    }
};

// ===== Weights struct =====
struct LeNetWeights {
    vector<float> conv1_w, conv1_b;
    vector<float> conv2_w, conv2_b;
    vector<float> fc1_w,  fc1_b;
    vector<float> fc2_w,  fc2_b;
    vector<float> fc3_w,  fc3_b;
    bool load(const string& dir){
        vector<int64_t> sh; vector<float> d;
        auto L = [&](const string& name, vector<float>& out){
            if (!load_npy_float32(dir + "/" + name + ".npy", sh, d)) return false;
            out.swap(d); return true;
        };
        return L("conv1_weight", conv1_w) && L("conv1_bias", conv1_b) &&
               L("conv2_weight", conv2_w) && L("conv2_bias", conv2_b) &&
               L("fc1_weight",  fc1_w) &&  L("fc1_bias",  fc1_b) &&
               L("fc2_weight",  fc2_w) &&  L("fc2_bias",  fc2_b) &&
               L("fc3_weight",  fc3_w) &&  L("fc3_bias",  fc3_b);
    }
};

// ===== Per-layer profiling struct =====
struct LayerTimes {
    double preprocess=0, conv1=0, pool1=0, conv2=0, pool2=0, fc1=0, fc2=0, fc3=0, total=0;
};

struct LayerErrors {
    ErrorMetrics conv1, pool1, conv2, pool2, fc1, fc2, fc3;
    void print_table() const {
        cout << "\n=== Per-Layer Error Metrics (INT8 vs FP32) ===\n";
        cout << left << setw(12) << "Layer" << right << setw(12) << "L1_avg" << setw(12) << "L2_RMS" << setw(12) << "Cosine" << "\n";
        cout << string(48, '-') << "\n";
        auto row = [&](const string& name, const ErrorMetrics& e){
            cout << left << setw(12) << name << right << setw(12) << scientific << setprecision(4) << e.l1
                 << setw(12) << e.l2 << setw(12) << fixed << setprecision(6) << e.cosine << "\n";
        };
        row("Conv1", conv1);
        row("Pool1", pool1);
        row("Conv2", conv2);
        row("Pool2", pool2);
        row("FC1", fc1);
        row("FC2", fc2);
        row("FC3", fc3);
        cout << "\n";
    }
};

// ===== Main inference (FP32 + INT8 with error tracking) =====
static int infer_compare(const vector<float>& img32, const LeNetWeights& W, LayerTimes& t_fp, LayerTimes& t_int, LayerErrors& errs) {
    // Precompute weight scales
    vector<float> w_scales_conv1, w_scales_conv2, w_scales_fc1, w_scales_fc2, w_scales_fc3;
    get_weight_scales_conv(W.conv1_w, 6, 1, 5, 5, w_scales_conv1);
    get_weight_scales_conv(W.conv2_w, 16, 6, 5, 5, w_scales_conv2);
    get_weight_scales_fc(W.fc1_w, 120, 400, w_scales_fc1);
    get_weight_scales_fc(W.fc2_w, 84, 120, w_scales_fc2);
    get_weight_scales_fc(W.fc3_w, 10, 84, w_scales_fc3);

    auto conv1_wq = quantize_weight_per_channel_conv(W.conv1_w, w_scales_conv1, 6, 1, 5, 5);
    auto conv2_wq = quantize_weight_per_channel_conv(W.conv2_w, w_scales_conv2, 16, 6, 5, 5);
    auto fc1_wq = quantize_weight_per_channel_fc(W.fc1_w, w_scales_fc1, 120, 400);
    auto fc2_wq = quantize_weight_per_channel_fc(W.fc2_w, w_scales_fc2, 84, 120);
    auto fc3_wq = quantize_weight_per_channel_fc(W.fc3_w, w_scales_fc3, 10, 84);

    // === FP32 path ===
    auto t0 = hrc::now();
    vector<float> x_fp(32*32);
    for (int i=0;i<32*32;++i) x_fp[i] = (img32[i] - 0.1307f) / 0.3081f;
    auto t1 = hrc::now();
    t_fp.preprocess = dur_us(t1-t0).count();

    auto conv1_fp = conv2d_fp32(x_fp, 1, 32, 32, W.conv1_w, W.conv1_b, 6, 5);
    relu_fp32_inplace(conv1_fp);
    auto t2 = hrc::now();
    t_fp.conv1 = dur_us(t2-t1).count();

    auto pool1_fp = maxpool2x2s2_fp32(conv1_fp, 6, 28, 28);
    auto t3 = hrc::now();
    t_fp.pool1 = dur_us(t3-t2).count();

    auto conv2_fp = conv2d_fp32(pool1_fp, 6, 14, 14, W.conv2_w, W.conv2_b, 16, 5);
    relu_fp32_inplace(conv2_fp);
    auto t4 = hrc::now();
    t_fp.conv2 = dur_us(t4-t3).count();

    auto pool2_fp = maxpool2x2s2_fp32(conv2_fp, 16, 10, 10);
    auto t5 = hrc::now();
    t_fp.pool2 = dur_us(t5-t4).count();

    auto fc1_fp = fc_fp32(pool2_fp, W.fc1_w, W.fc1_b, 400, 120);
    relu_fp32_inplace(fc1_fp);
    auto t6 = hrc::now();
    t_fp.fc1 = dur_us(t6-t5).count();

    auto fc2_fp = fc_fp32(fc1_fp, W.fc2_w, W.fc2_b, 120, 84);
    relu_fp32_inplace(fc2_fp);
    auto t7 = hrc::now();
    t_fp.fc2 = dur_us(t7-t6).count();

    auto fc3_fp = fc_fp32(fc2_fp, W.fc3_w, W.fc3_b, 84, 10);
    auto t8 = hrc::now();
    t_fp.fc3 = dur_us(t8-t7).count();
    t_fp.total = dur_us(t8-t0).count();

    // === INT8 path ===
    auto t0i = hrc::now();
    vector<float> x_int = x_fp;
    float x_scale = max_abs(x_int)/127.0f; if(x_scale<=0) x_scale=1.0f;
    auto x_q = quantize_tensor_int8(x_int, x_scale);
    auto t1i = hrc::now();
    t_int.preprocess = dur_us(t1i-t0i).count();

    auto conv1_int = conv2d_int8(x_q, x_scale, 1, 32, 32, conv1_wq, w_scales_conv1, W.conv1_b, 6, 5);
    float conv1_scale = max_abs(conv1_int)/127.0f; if(conv1_scale<=0) conv1_scale=1.0f;
    conv1_int = relu_int8(conv1_int, conv1_scale);
    auto t2i = hrc::now();
    t_int.conv1 = dur_us(t2i-t1i).count();
    errs.conv1.compute(conv1_fp, conv1_int);

    auto pool1_int = maxpool2x2s2_int8(conv1_int, conv1_scale, 6, 28, 28);
    auto t3i = hrc::now();
    t_int.pool1 = dur_us(t3i-t2i).count();
    errs.pool1.compute(pool1_fp, pool1_int);

    float pool1_scale = max_abs(pool1_int)/127.0f; if(pool1_scale<=0) pool1_scale=1.0f;
    auto pool1_q = quantize_tensor_int8(pool1_int, pool1_scale);
    auto conv2_int = conv2d_int8(pool1_q, pool1_scale, 6, 14, 14, conv2_wq, w_scales_conv2, W.conv2_b, 16, 5);
    float conv2_scale = max_abs(conv2_int)/127.0f; if(conv2_scale<=0) conv2_scale=1.0f;
    conv2_int = relu_int8(conv2_int, conv2_scale);
    auto t4i = hrc::now();
    t_int.conv2 = dur_us(t4i-t3i).count();
    errs.conv2.compute(conv2_fp, conv2_int);

    auto pool2_int = maxpool2x2s2_int8(conv2_int, conv2_scale, 16, 10, 10);
    auto t5i = hrc::now();
    t_int.pool2 = dur_us(t5i-t4i).count();
    errs.pool2.compute(pool2_fp, pool2_int);

    float pool2_scale = max_abs(pool2_int)/127.0f; if(pool2_scale<=0) pool2_scale=1.0f;
    auto fc1_int = fc_int8(pool2_int, pool2_scale, fc1_wq, w_scales_fc1, W.fc1_b, 400, 120);
    float fc1_scale = max_abs(fc1_int)/127.0f; if(fc1_scale<=0) fc1_scale=1.0f;
    fc1_int = relu_int8(fc1_int, fc1_scale);
    auto t6i = hrc::now();
    t_int.fc1 = dur_us(t6i-t5i).count();
    errs.fc1.compute(fc1_fp, fc1_int);

    auto fc2_int = fc_int8(fc1_int, fc1_scale, fc2_wq, w_scales_fc2, W.fc2_b, 120, 84);
    float fc2_scale = max_abs(fc2_int)/127.0f; if(fc2_scale<=0) fc2_scale=1.0f;
    fc2_int = relu_int8(fc2_int, fc2_scale);
    auto t7i = hrc::now();
    t_int.fc2 = dur_us(t7i-t6i).count();
    errs.fc2.compute(fc2_fp, fc2_int);

    auto fc3_int = fc_int8(fc2_int, fc2_scale, fc3_wq, w_scales_fc3, W.fc3_b, 84, 10);
    auto t8i = hrc::now();
    t_int.fc3 = dur_us(t8i-t7i).count();
    t_int.total = dur_us(t8i-t0i).count();
    errs.fc3.compute(fc3_fp, fc3_int);

    return argmax(fc3_int);
}

// ===== Main =====
int main(int argc, char* argv[]) {
    string images_path = ".\\dataset\\MNIST\\raw\\t10k-images-idx3-ubyte";
    string labels_path = ".\\dataset\\MNIST\\raw\\t10k-labels-idx1-ubyte";
    string weights_dir = ".\\artifacts\\lenet_weights\\float32";
    int sample_idx = 0;
    int batch_size = 100;

    for (int i=1;i<argc;++i){
        string a = argv[i];
        auto next = [&](string& dst){ if (i+1<argc) dst=argv[++i]; };
        if (a=="--images") next(images_path);
        else if (a=="--labels") next(labels_path);
        else if (a=="--weights_dir") next(weights_dir);
        else if (a=="--sample") { if (i+1<argc) sample_idx = stoi(argv[++i]); }
        else if (a=="--batch") { if (i+1<argc) batch_size = stoi(argv[++i]); }
    }
    cout << "=== Configuration ===\n"
         << "Images: " << images_path << "\nLabels: " << labels_path
         << "\nWeights: " << weights_dir << "\nBatch: " << batch_size << "\n";

    vector<vector<float>> imgs28; vector<int> labels;
    if (!read_mnist_images(images_path, imgs28)) return -1;
    if (!read_mnist_labels(labels_path, labels)) return -1;

    LeNetWeights W;
    if (!W.load(weights_dir)) { cerr << "Load weights failed\n"; return -1; }

    int end = min(sample_idx + batch_size, int(imgs28.size()));
    int correct_int8 = 0;
    LayerTimes total_fp, total_int;
    LayerErrors total_errs;

    for (int idx=sample_idx; idx<end; ++idx){
        auto img32 = resize_bilinear(imgs28[idx], 28, 28, 32, 32);
        LayerTimes t_fp, t_int;
        LayerErrors errs;
        int pred = infer_compare(img32, W, t_fp, t_int, errs);
        if (pred == labels[idx]) ++correct_int8;

        total_fp.preprocess += t_fp.preprocess; total_fp.conv1 += t_fp.conv1; total_fp.pool1 += t_fp.pool1;
        total_fp.conv2 += t_fp.conv2; total_fp.pool2 += t_fp.pool2; total_fp.fc1 += t_fp.fc1;
        total_fp.fc2 += t_fp.fc2; total_fp.fc3 += t_fp.fc3; total_fp.total += t_fp.total;

        total_int.preprocess += t_int.preprocess; total_int.conv1 += t_int.conv1; total_int.pool1 += t_int.pool1;
        total_int.conv2 += t_int.conv2; total_int.pool2 += t_int.pool2; total_int.fc1 += t_int.fc1;
        total_int.fc2 += t_int.fc2; total_int.fc3 += t_int.fc3; total_int.total += t_int.total;

        total_errs.conv1.l1 += errs.conv1.l1; total_errs.conv1.l2 += errs.conv1.l2; total_errs.conv1.cosine += errs.conv1.cosine;
        total_errs.pool1.l1 += errs.pool1.l1; total_errs.pool1.l2 += errs.pool1.l2; total_errs.pool1.cosine += errs.pool1.cosine;
        total_errs.conv2.l1 += errs.conv2.l1; total_errs.conv2.l2 += errs.conv2.l2; total_errs.conv2.cosine += errs.conv2.cosine;
        total_errs.pool2.l1 += errs.pool2.l1; total_errs.pool2.l2 += errs.pool2.l2; total_errs.pool2.cosine += errs.pool2.cosine;
        total_errs.fc1.l1 += errs.fc1.l1; total_errs.fc1.l2 += errs.fc1.l2; total_errs.fc1.cosine += errs.fc1.cosine;
        total_errs.fc2.l1 += errs.fc2.l1; total_errs.fc2.l2 += errs.fc2.l2; total_errs.fc2.cosine += errs.fc2.cosine;
        total_errs.fc3.l1 += errs.fc3.l1; total_errs.fc3.l2 += errs.fc3.l2; total_errs.fc3.cosine += errs.fc3.cosine;
    }

    int n = end - sample_idx;
    total_errs.conv1.l1/=n; total_errs.conv1.l2/=n; total_errs.conv1.cosine/=n;
    total_errs.pool1.l1/=n; total_errs.pool1.l2/=n; total_errs.pool1.cosine/=n;
    total_errs.conv2.l1/=n; total_errs.conv2.l2/=n; total_errs.conv2.cosine/=n;
    total_errs.pool2.l1/=n; total_errs.pool2.l2/=n; total_errs.pool2.cosine/=n;
    total_errs.fc1.l1/=n; total_errs.fc1.l2/=n; total_errs.fc1.cosine/=n;
    total_errs.fc2.l1/=n; total_errs.fc2.l2/=n; total_errs.fc2.cosine/=n;
    total_errs.fc3.l1/=n; total_errs.fc3.l2/=n; total_errs.fc3.cosine/=n;

    cout << "\n=== Results (INT8) ===\n"
         << "Batch: " << n << " images\n"
         << "Correct: " << correct_int8 << " / " << n << " (" << fixed << setprecision(2) << 100.0*correct_int8/n << "%)\n";

    cout << "\n=== Average Time per Image (microseconds) ===\n";
    cout << left << setw(12) << "Mode" << right << setw(12) << "Total(us)" << setw(12) << "Conv1" << setw(12) << "Conv2" << "\n";
    cout << string(48, '-') << "\n";
    cout << left << setw(12) << "FP32" << right << setw(12) << fixed << setprecision(2) << total_fp.total/n
         << setw(12) << total_fp.conv1/n << setw(12) << total_fp.conv2/n << "\n";
    cout << left << setw(12) << "INT8" << right << setw(12) << total_int.total/n
         << setw(12) << total_int.conv1/n << setw(12) << total_int.conv2/n << "\n\n";

    total_errs.print_table();

    return 0;
}