import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
from torchvision import datasets, transforms
import time
from matplotlib import pyplot as plt
 
pipline_train = transforms.Compose([
    # 随机旋转图片
    # MNIST 是手写数字数据集，左右翻转可能造成语义错误（例如，6 和 9 会被混淆）。所以不建议使用
    # transforms.RandomHorizontalFlip(),
    # 将图片尺寸resize到32x32
    transforms.Resize((32, 32)),
    # 将图片转化为Tensor格式
    transforms.ToTensor(),
    # 正则化(当模型出现过拟合的情况时，用来降低模型的复杂度)
    transforms.Normalize((0.1307,), (0.3081,))
])
pipline_test = transforms.Compose([
    # 将图片尺寸resize到32x32
    transforms.Resize((32, 32)),
    transforms.ToTensor(),
    transforms.Normalize((0.1307,), (0.3081,))
])
# 下载数据集
train_set = datasets.MNIST(root="./dataset", train=True, download=True, transform=pipline_train)
test_set = datasets.MNIST(root="./dataset", train=False, download=True, transform=pipline_test)
# 加载数据集
trainloader = torch.utils.data.DataLoader(train_set, batch_size=64, shuffle=True)
testloader = torch.utils.data.DataLoader(test_set, batch_size=32, shuffle=False)
 
 
# 构建LeNet模型
class LeNet(nn.Module):
    def __init__(self):
        super(LeNet, self).__init__()
        self.conv1 = nn.Conv2d(1, 6, 5)
        self.relu = nn.ReLU()
        self.maxpool1 = nn.MaxPool2d(2, 2)
        self.conv2 = nn.Conv2d(6, 16, 5)
        self.maxpool2 = nn.MaxPool2d(2, 2)
        self.fc1 = nn.Linear(16 * 5 * 5, 120)
        self.fc2 = nn.Linear(120, 84)
        self.fc3 = nn.Linear(84, 10)
 
    def forward(self, x):
        x = self.conv1(x)
        x = self.relu(x)
        x = self.maxpool1(x)
        x = self.conv2(x)
        x = self.maxpool2(x)
        x = x.view(-1, 16 * 5 * 5)
        x = F.relu(self.fc1(x))
        x = F.relu(self.fc2(x))
        x = self.fc3(x)
        return x
 
 
# 创建模型，部署gpu
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
model = LeNet().to(device)
# 定义优化器
optimizer = optim.Adam(model.parameters(), lr=0.001)
 
 
def train_runner(model, device, trainloader, optimizer, epoch):
    model.train()
    total_loss = 0
    total_correct = 0
    total_samples = 0
 
    for i, (inputs, labels) in enumerate(trainloader):
        inputs, labels = inputs.to(device), labels.to(device)
        optimizer.zero_grad()
        outputs = model(inputs)
        loss = F.cross_entropy(outputs, labels)
        predict = outputs.argmax(dim=1)
        correct = (predict == labels).sum().item()
 
        loss.backward()
        optimizer.step()
 
        total_loss += loss.item()
        total_correct += correct
        total_samples += labels.size(0)
 
        if i % 100 == 0:
            print(f"Epoch {epoch}, Batch {i}, Loss: {loss.item():.6f}, Accuracy: {correct / labels.size(0) * 100:.2f}%")
 
    avg_loss = total_loss / len(trainloader)
    avg_acc = total_correct / total_samples
    print(f"Epoch {epoch} - Average Loss: {avg_loss:.6f}, Accuracy: {avg_acc * 100:.2f}%")
    return avg_loss, avg_acc
 
 
def test_runner(model, device, testloader):
    # 模型验证, 必须要写, 否则只要有输入数据, 即使不训练, 它也会改变权值
    # 因为调用eval()将不启用 BatchNormalization 和 Dropout, BatchNormalization和Dropout置为False
    model.eval()
    # 统计模型正确率, 设置初始值
    correct = 0.0
    test_loss = 0.0
    total = 0
    # torch.no_grad将不会计算梯度, 也不会进行反向传播
    with torch.no_grad():
        for data, label in testloader:
            data, label = data.to(device), label.to(device)
            output = model(data)
            test_loss += F.cross_entropy(output, label).item()
            predict = output.argmax(dim=1)
            # 计算正确数量
            total += label.size(0)
            correct += (predict == label).sum().item()
        # 计算损失值
        print("test_avarage_loss: {:.6f}, accuracy: {:.6f}%".format(test_loss / total, 100 * (correct / total)))
 
 
# 调用
epoch = 5
Loss = []
Accuracy = []
for epoch in range(1, epoch + 1):
    print("start_time", time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(time.time())))
    loss, acc = train_runner(model, device, trainloader, optimizer, epoch)
    Loss.append(loss)
    Accuracy.append(acc)
    test_runner(model, device, testloader)
    print("end_time: ", time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(time.time())), '\n')
 
print('Finished Training')

# 保存模型参数用于导出
torch.save(model.state_dict(), "lenet_mnist.pth")
print("模型参数已保存到: lenet_mnist.pth")

plt.figure(figsize=(10, 5))
plt.subplot(1, 2, 1)
plt.plot(Loss)
plt.title('Training Loss')
plt.xlabel('Epoch')
plt.ylabel('Loss')
 
plt.subplot(1, 2, 2)
plt.plot(Accuracy)
plt.title('Training Accuracy')
plt.xlabel('Epoch')
plt.ylabel('Accuracy')
plt.tight_layout()
plt.show()