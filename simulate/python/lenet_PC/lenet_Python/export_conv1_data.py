import torch, numpy as np
from test_lenet import LeNet
from torchvision import datasets, transforms

model = LeNet()
state = torch.load("lenet_mnist.pth", map_location="cpu")
model.load_state_dict(state)
model.eval()

# MNIST sample
dataset = datasets.MNIST("./data", train=False, download=True,
                         transform=transforms.ToTensor())
x, _ = dataset[0]
x = x.unsqueeze(0)

with torch.no_grad():
    ref = model.conv1(x)
    np.save("ref_conv1_out.npy", ref.numpy())
    np.save("input_image_int8.npy", (x.numpy()*127).astype(np.int8))
    np.save("conv1_weight_int8.npy", (model.conv1.weight.numpy()*127).astype(np.int8))
    np.save("conv1_bias_int8.npy", (model.conv1.bias.numpy()*127).astype(np.int8))
