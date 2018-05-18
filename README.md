# Lab 2: Building a Convolutional Neural Network

## Introduction
In this lab we're going to improve on our linear classifier by building a convolutional neural network. You should see your accuracy go way up!

We're going to ask you to focus mainly on implementing the kernel (OpenCL) portion of this. Don't worry about doing any heavy optimization; we're just looking for a baseline implementation here.

There are only two other informational sections to this handout (besides what you need to do and what you need to submit) - one describing the architecture (layer parameters) of the CNN we're going to implement, and another detailing how exactly each layer works (which should be helpful if you haven't had any coursework in neural networks before). We're not going to describe the semantics of emulation/compilation because they should be largely the same as before! Refer to lab 1 if you need a refresher. 

## Your Task
Complete the following:
1. Modify main.cpp to work for our CNN. (HINT: Reference lab 1, and extend it for the larger numbers of weights you'll need to feed to the kernel)
2. Complete cnn.cl to implement a forward pass of the CNN described.
3. Run synthesis. While we still haven't been able to sort out exactly what was going on when we tried to program the boards, we're asking you to synthesize what you have and make sure it actually fits on the FPGA! With a large enough network, this is not necessarily a foregone conclusion. If you can synthesize fully, you're fine - if not you'll get an error message telling you how far over the limit of logical elements you are.

### Tips
- Use the same workflow as last time. Modify your .cpp and .cl files, and then emulate to show functional correctness.
- You may find that trying to verify correctness on the full 10000-element test set takes a long time. If you change your workgroup to a smaller number of items (change this in both the .cl and .cpp files) you'll be able to get results more quickly.
- When debugging your kernel, it might be helpful to know that you can add print statements! Just remember to remove them before you synthesize fully.

## What To Submit
- A pdf, with your accuracy and runtime for 100 examples of the 10000-element test set (modify work group size as mentioned above). Also include your area metrics and synthesis outputs.
- Your entire project directory.

Zip these up and submit on canvas by the deadline!

## Layer Parameters
### Layer 1: Conv
- Filter Size: 5x5
- Number of Filters: 32
- Padding: 'Same'
- Activation Function: ReLU

### Layer 2: Maxpool
- Filter Size: 2x2
- Stride: 2

### Layer 3: Conv
- Filter Size: 5x5
- Number of Filters: 64
- Padding: 'Same'
- Activation Function: ReLU

### Layer 4: Maxpool
- Filter size: 2x2
- Stride: 2

### Layer 5: Dense (fully connected)
- Number of nodes: 256
- Activation Function: ReLU

### Layer 6: Softmax (also fully connected)
- Number of nodes: 10
- After you have the output of each of the ten nodes (one for each digit your input might represent), find which node has the largest output. That's your prediction!

### Dimensions
- Input: 28 x 28 x 1
- After layer 1: 28 \* 28 \* 32
- After layer 2: 14 \* 14 \* 32
- After layer 3: 14 \* 14 \* 64
- After layer 4: 7 \* 7 \* 64
- After layer 5: 256 \* 1 \* 1


## Implementation Guide

### Convolutional layers
For these layers the weights we've given you are going to correspond to the elements in a number of 'filters', each with the size given (in this case, both convolutional layers have filters of size 5x5). To perform the convolution all you need to do is slide this filter along the input to that layer and multiply each element of the filter by the 'matching' elements of the input.

As an example, let's say you have an input and a filter that look like this (a 3x3 input and a 2x2 filter):
```
Input x: 
[1, 2, 3,
 4, 5, 6,
 7, 8, 9]
 
Filter f:
[1, 2,
 3, 4]
```
To convolve that filter over that input, you would first place the filter over the top left part of the input - so x<sub>1,1</sub> and f<sub>1,1</sub> correspond to each other. Then multiply all the corresponding elements and add the results to get output<sub>1,1</sub>. In this case, that would be:

x<sub>1,1</sub>\*f<sub>1,1</sub> + x<sub>1,2</sub>\*f<sub>1,2</sub> + x<sub>2,1</sub>\*f<sub>2,1</sub> + x<sub>2,2</sub>\*f<sub>2,2</sub> \
or concretely,\
1\*1 + 2\*2 + 4\*3 + 5\*4 = 37

So the element in the top right corner of your output would be 37. Repeat this process again, but this time sliding your filter to the right one space (so your multiplication would look like 2\*1 + 3\*2 + 5\*3 + 6\*4 = 47). That result would be the next element of your output. Then slide the filter down to the next row, and repeat. After you're done you would get the following:
```
[37, 47,
 67, 77]
```
After that we add the bias (another number we give you) to each element. And finally, the last thing you would have to do is apply our activation function to each element. In our case that's the ReLU function, and since all these are positive they'll stay the same.

Great! We're done with our multiplications. The only problem here is that we've lost some size when we went from input to output, i.e. our input was 3x3 and our output was 2x2. Both our convolutional layers have 'same' padding, which means that we want to preserve the input size. To do that we'll just artificially layer our input with zeros around the edges, like so:

```
[0, 0, 0, 0,
 0, 1, 2, 3,
 0, 4, 5, 6,
 0, 7, 8, 9]
```
Notice that if our dimensions called for it, we might need to add padding on the right and bottom sides of the matrix as well.

The last thing you need to understand about these layers is that we have multiple filters. We just went through an example with one filter, and it produced one matrix. When you have 32 filters (as we do in our first convolutional layer, for example), you're going to produce 32 matrices. All of these together will be that layer's output. We say that this is an output with 32 *channels*.

If you then, in turn, use those 32 channels as the input to another convolutional layer, you're going to need a filter with 32 channels as well. In that case you apply each channel of the filter to one channel of the input, and then sum across the similar elements in all your results to get one output matrix. As an example, output<sub>3,2</sub> would be the sum of result<sub>3,2</sub> for each of the 32 matrices you got by convolving one channel of the input with one channel of the filter.

Note that if we have an input with 32 channels and pass it through a convolutional layer with 64 filters, it's implied that each of those filters will have 32 channels. Dimensions can be one of the most difficult parts of working with neural networks, so make sure you understand where each of the numbers in the 'dimensions' part of the Architecture section are coming from before you start working.

### Maxpool layers

Maxpool layers are much easier to deal with. We just take our filter (in our case, a 2x2 window) and slide it over the input like before. But instead of having to do multiplications, our result is just the largest element of the input that our filter covers. As an example, let's say we have the following input:
```
[5, 8, 4, 3,
 6, 3, 7, 2,
 4, 3, 2, 1,
 1, 5, 6, 9]
 ```
If we use a filter size of 2x2 and a stride of 2 (moving our filter over by 2 spaces every time instead of just 1 like before), our output will be:
```
[8, 7,
 5, 9]
```
Where
- output<sub>1,1</sub> is computed from max(5,8,6,3)
- output<sub>1,2</sub> is computed from max(4,3,7,2)
- output<sub>2,1</sub> is computed from max(4,3,1,5)
- output<sub>2,2</sub> is computed from max(2,1,6,9)

Make sure you understand how all these match up to the input! \
Again, you'll notice we lose size here, but for Maxpool layers that's fine. Maxpooling also doesn't change the number of channels we have since you just apply the filter to each channel separately. There's no summing or max-ing involved across channels.

### Fully Connected Layers

This one is also pretty easy to do - it's more or less the same as the linear classifier from last time, but with an activation function at the end. \
The input to each node in our fully connected layer will be one of two things, depending on the type of layer that came before it:
- Our first fully connected layer comes right after a softmax layer. The output of this layer is 64 7x7 matrices. To turn this into an input, we'll flatten each of the matrices (turning them into a 1-dimensional vector of length 49) and then concatenate all 64 of them together.
- Our second and final fully connected layer comes right after our first fully connected layer. The output of the first FC layer is 256 different numbers, so we'll just smush those together into a 1-dimensional vector of length 256 and make that the input to each node in our second FC layer.

For both layers, we give you weight vectors for each node. Each one will have exactly the same number of elements as that node's input. To get the output simply dot the input vector and the weight vector, add the node's bias (another parameter we give you with the weights) and apply the activation function. The output of a node will be a single number.

### Softmax Layer

For our final layer we have ten nodes - one for each of the digits we might see, 0-9. The output of each node will correspond to the probability that the input we've processed is that node's digit. Simply pick the largest probability of all ten nodes, and use the matching digit as your prediction! (This isn't technically how softmax works exactly, but for our purposes it's good enough)
