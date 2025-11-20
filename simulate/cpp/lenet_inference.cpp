// LeNet inference on MNIST with per-layer performance profiling
// Build: cl /O2 /std:c++17 lenet_inference.cpp  (or g++ -O3 -std=c++17 -o lenet_inference lenet_inference.cpp)
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

// ===== Utility: Load .npy (float32, little-endian, C-order) =====
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

// ===== Read MNIST idx images (28x28, then bilinear resize to 32x32) =====
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

// ===== Fake quantization helpers =====
static inline float fake_fp16(float x) {
    if (x==0.0f) return 0.0f;
    int e; float m = frexp(x, &e);
    float q = ldexp(round(m*1024.0f), -10);
    return ldexp(copysign(q, m), e);
}
static inline float fake_int8_qdq(float x, float scale) {
    if (scale<=0) return x;
    float q = round(x/scale);
    q = min(max(q, -128.0f), 127.0f);
    return q*scale;
}
static void qdq_tensor(vector<float>& x, float scale) {
    for (auto& v: x) v = fake_int8_qdq(v, scale);
}
static float max_abs(const vector<float>& x){
    float m=0.0f; for (auto v: x) m = max(m, fabs(v)); return m;
}

// ===== Activation =====
static inline float relu_act(float x) { return x>0?x:0; }

// ===== Conv2d valid (stride=1, no padding) =====
static vector<float> conv2d_valid(const vector<float>& x, int Cin, int Hin, int Win,
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
                            int ih = oh + kh, iw = ow + kw;
                            float xv = x[ic*Hin*Win + ih*Win + iw];
                            float wv = w[oc*Cin*K*K + ic*K*K + kh*K + kw];
                            acc += xv * wv;
                        }
                    }
                }
                y[oc*Hout*Wout + oh*Wout + ow] = acc;
            }
        }
    }
    return y;
}

static void relu_inplace(vector<float>& x){ for (auto& v: x) v = relu_act(v); }

// ===== MaxPool 2x2 stride=2 =====
static vector<float> maxpool2x2s2(const vector<float>& x, int C, int H, int W) {
    int Hout = H/2, Wout = W/2;
    vector<float> y(C*Hout*Wout);
    for (int c=0;c<C;++c){
        for (int oh=0;oh<Hout;++oh){
            for (int ow=0;ow<Wout;++ow){
                float m = -1e30f;
                for (int kh=0;kh<2;++kh){
                    for (int kw=0;kw<2;++kw){
                        int ih = oh*2 + kh, iw = ow*2 + kw;
                        m = max(m, x[c*H*W + ih*W + iw]);
                    }
                }
                y[c*Hout*Wout + oh*Wout + ow] = m;
            }
        }
    }
    return y;
}

// ===== Fully connected =====
static vector<float> fc_layer(const vector<float>& x, const vector<float>& w, const vector<float>& b,
                               int In, int Out) {
    vector<float> out(Out);
    for (int o=0;o<Out;++o){
        float acc = b[o];
        const float* row = w.data() + o*In;
        for (int i=0;i<In;++i) acc += row[i]*x[i];
        out[o] = acc;
    }
    return out;
}

static int argmax(const vector<float>& x){
    return int(max_element(x.begin(), x.end()) - x.begin());
}

// ===== LeNet weights struct =====
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

// ===== Performance profiling struct =====
struct LayerTimes {
    double preprocess_us=0, conv1_us=0, pool1_us=0, conv2_us=0, pool2_us=0, fc1_us=0, fc2_us=0, fc3_us=0, total_us=0;
    void print_table() const {
        cout << "\n=== Per-Layer Performance (microseconds) ===\n";
        cout << left << setw(15) << "Layer" << right << setw(12) << "Time(us)" << setw(10) << "%" << "\n";
        cout << string(37, '-') << "\n";
        auto row = [&](const string& name, double t){
            cout << left << setw(15) << name << right << setw(12) << fixed << setprecision(2) << t
                 << setw(9) << fixed << setprecision(1) << (total_us>0 ? 100.0*t/total_us : 0) << "%\n";
        };
        row("Preprocess", preprocess_us);
        row("Conv1+ReLU", conv1_us);
        row("Pool1", pool1_us);
        row("Conv2+ReLU", conv2_us);
        row("Pool2", pool2_us);
        row("FC1+ReLU", fc1_us);
        row("FC2+ReLU", fc2_us);
        row("FC3", fc3_us);
        cout << string(37, '-') << "\n";
        row("TOTAL", total_us);
        cout << "\n";
    }
};

// ===== Single image inference with profiling =====
static int infer_one_profiled(const vector<float>& img32, const LeNetWeights& W, const string& mode, LayerTimes& times) {
    auto t0 = hrc::now();
    
    // Preprocess: normalize
    vector<float> x(32*32);
    for (int i=0;i<32*32;++i) x[i] = (img32[i] - 0.1307f) / 0.3081f;
    if (mode=="fp16") { for (auto& v: x) v = fake_fp16(v); }
    else if (mode=="int8") { float s=max_abs(x)/127.0f; if(s<=0)s=1; qdq_tensor(x,s); }
    auto t1 = hrc::now();
    times.preprocess_us = dur_us(t1 - t0).count();

    // Conv1+ReLU: 1x32x32 -> 6x28x28
    auto y1 = conv2d_valid(x, 1, 32, 32, W.conv1_w, W.conv1_b, 6, 5);
    relu_inplace(y1);
    if (mode=="fp16") { for (auto& v: y1) v = fake_fp16(v); }
    else if (mode=="int8") { float s=max_abs(y1)/127.0f; if(s<=0)s=1; qdq_tensor(y1,s); }
    auto t2 = hrc::now();
    times.conv1_us = dur_us(t2 - t1).count();

    // Pool1 -> 6x14x14
    auto p1 = maxpool2x2s2(y1, 6, 28, 28);
    auto t3 = hrc::now();
    times.pool1_us = dur_us(t3 - t2).count();

    // Conv2+ReLU: 6x14x14 -> 16x10x10
    auto y2 = conv2d_valid(p1, 6, 14, 14, W.conv2_w, W.conv2_b, 16, 5);
    relu_inplace(y2);
    if (mode=="fp16") { for (auto& v: y2) v = fake_fp16(v); }
    else if (mode=="int8") { float s=max_abs(y2)/127.0f; if(s<=0)s=1; qdq_tensor(y2,s); }
    auto t4 = hrc::now();
    times.conv2_us = dur_us(t4 - t3).count();

    // Pool2 -> 16x5x5 = 400
    auto p2 = maxpool2x2s2(y2, 16, 10, 10);
    auto t5 = hrc::now();
    times.pool2_us = dur_us(t5 - t4).count();

    // FC1+ReLU 400->120
    auto f1 = fc_layer(p2, W.fc1_w, W.fc1_b, 400, 120);
    relu_inplace(f1);
    if (mode=="fp16") { for (auto& v: f1) v = fake_fp16(v); }
    else if (mode=="int8") { float s=max_abs(f1)/127.0f; if(s<=0)s=1; qdq_tensor(f1,s); }
    auto t6 = hrc::now();
    times.fc1_us = dur_us(t6 - t5).count();

    // FC2+ReLU 120->84
    auto f2 = fc_layer(f1, W.fc2_w, W.fc2_b, 120, 84);
    relu_inplace(f2);
    if (mode=="fp16") { for (auto& v: f2) v = fake_fp16(v); }
    else if (mode=="int8") { float s=max_abs(f2)/127.0f; if(s<=0)s=1; qdq_tensor(f2,s); }
    auto t7 = hrc::now();
    times.fc2_us = dur_us(t7 - t6).count();

    // FC3 84->10
    auto logits = fc_layer(f2, W.fc3_w, W.fc3_b, 84, 10);
    auto t8 = hrc::now();
    times.fc3_us = dur_us(t8 - t7).count();

    times.total_us = dur_us(t8 - t0).count();
    return argmax(logits);
}

// ===== Main =====
int main(int argc, char* argv[]) {
    string images_path = ".\\dataset\\MNIST\\raw\\t10k-images-idx3-ubyte";
    string labels_path = ".\\dataset\\MNIST\\raw\\t10k-labels-idx1-ubyte";
    string weights_dir = ".\\artifacts\\lenet_weights\\float32";
    string mode = "fp32";  // fp32 | fp16 | int8
    int sample_idx = 0;
    int batch_size = 1;  // batch inference

    for (int i=1;i<argc;++i){
        string a = argv[i];
        auto next = [&](string& dst){ if (i+1<argc) dst=argv[++i]; };
        if (a=="--images") next(images_path);
        else if (a=="--labels") next(labels_path);
        else if (a=="--weights_dir") next(weights_dir);
        else if (a=="--mode") next(mode);
        else if (a=="--sample") { if (i+1<argc) sample_idx = stoi(argv[++i]); }
        else if (a=="--batch") { if (i+1<argc) batch_size = stoi(argv[++i]); }
    }
    cout << "=== Configuration ===\n"
         << "Images: " << images_path << "\nLabels: " << labels_path
         << "\nWeights: " << weights_dir << "\nMode: " << mode
         << "\nSample index: " << sample_idx << "\nBatch size: " << batch_size << "\n";

    // Load test set
    vector<vector<float>> imgs28; vector<int> labels;
    if (!read_mnist_images(images_path, imgs28)) return -1;
    if (!read_mnist_labels(labels_path, labels)) return -1;
    if (imgs28.size() != labels.size()) { cerr << "Size mismatch\n"; return -1; }

    // Load weights
    LeNetWeights W;
    if (!W.load(weights_dir)) { cerr << "Load weights failed\n"; return -1; }

    // Batch inference
    int end_idx = min(sample_idx + batch_size, int(imgs28.size()));
    int correct = 0;
    LayerTimes total_times;

    for (int idx = sample_idx; idx < end_idx; ++idx) {
        auto img32 = resize_bilinear(imgs28[idx], 28, 28, 32, 32);
        LayerTimes t;
        int pred = infer_one_profiled(img32, W, mode, t);
        if (pred == labels[idx]) ++correct;
        
        total_times.preprocess_us += t.preprocess_us;
        total_times.conv1_us += t.conv1_us;
        total_times.pool1_us += t.pool1_us;
        total_times.conv2_us += t.conv2_us;
        total_times.pool2_us += t.pool2_us;
        total_times.fc1_us += t.fc1_us;
        total_times.fc2_us += t.fc2_us;
        total_times.fc3_us += t.fc3_us;
        total_times.total_us += t.total_us;
    }

    int n = end_idx - sample_idx;
    LayerTimes avg_times;
    avg_times.preprocess_us = total_times.preprocess_us / n;
    avg_times.conv1_us = total_times.conv1_us / n;
    avg_times.pool1_us = total_times.pool1_us / n;
    avg_times.conv2_us = total_times.conv2_us / n;
    avg_times.pool2_us = total_times.pool2_us / n;
    avg_times.fc1_us = total_times.fc1_us / n;
    avg_times.fc2_us = total_times.fc2_us / n;
    avg_times.fc3_us = total_times.fc3_us / n;
    avg_times.total_us = total_times.total_us / n;

    cout << "\n=== Results ===\n"
         << "Batch: " << n << " images\n"
         << "Correct: " << correct << " / " << n << " (" << 100.0*correct/n << "%)\n"
         << "Total time: " << fixed << setprecision(2) << total_times.total_us/1000.0 << " ms\n"
         << "Avg per image: " << fixed << setprecision(2) << avg_times.total_us/1000.0 << " ms\n"
         << "Throughput: " << fixed << setprecision(1) << 1e6/(avg_times.total_us) << " images/sec\n";

    avg_times.print_table();

    return 0;
}
