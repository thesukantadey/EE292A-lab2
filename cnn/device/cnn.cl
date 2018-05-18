// TODO: Define any constants you'll need
// image is a 28x28xN array (N images) of bytes (each pixel is 8 bit grayscale)

// TODO: If you decide you'd like to write helper functions, you can define them here


// TODO: Build a CNN!
__attribute__((reqd_work_group_size(10000,1,1))) // change this to change workgroup size
__kernel void linear_classifier(global const unsigned char * restrict images, 
								constant float * restrict conv1_weights,
								constant float * restrict conv1_bias,
								constant float * restrict conv2_weights,
								constant float * restrict conv2_bias,
								constant float * restrict dense1_weights,
								constant float * restrict dense1_bias,
								constant float * restrict dense2_weights,
								constant float * restrict dense2_bias,
								global unsigned char * restrict guesses)
{
	/* CONV LAYER 1 */

	/* MAXPOOL LAYER 1 */

	/* CONV LAYER 2 */

	/* MAXPOOL LAYER 2 */

	/* DENSE LAYER */

	/* DENSE 2 */
	
	/* FINAL GUESS */
	guesses[get_global_id(0)] = 0;
}
