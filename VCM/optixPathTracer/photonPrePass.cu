/* 
 * Copyright (c) 2016, NVIDIA CORPORATION. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of NVIDIA CORPORATION nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <optixu/optixu_math_namespace.h>
#include "optixPathTracer.h"
#include "random.h"
#include <stdio.h>

using namespace optix;

struct PerRayData_pathtrace
{
    float3 result;
    float3 radiance;
    float3 attenuation;
    float3 origin;
    float3 direction;
    unsigned int seed;
    int depth;
    int countEmitted;
    int done;

	float tValue;
	int isSpecular;
	float rayPdf;
};

struct PerRayData_pathtrace_shadow
{
    bool inShadow;
};

// Scene wide variables
rtDeclareVariable(float,         scene_epsilon, , );
rtDeclareVariable(rtObject,      top_object, , );
rtDeclareVariable(uint2,         launch_index, rtLaunchIndex, );

rtDeclareVariable(PerRayData_pathtrace, current_prd, rtPayload, );



//-----------------------------------------------------------------------------
//
//  Camera program -- main ray tracing loop
//
//-----------------------------------------------------------------------------

rtDeclareVariable(float3,        eye, , );
rtDeclareVariable(float3,        U, , );
rtDeclareVariable(float3,        V, , );
rtDeclareVariable(float3,        W, , );
rtDeclareVariable(float3,        bad_color, , );
rtDeclareVariable(unsigned int,  frame_number, , );
rtDeclareVariable(unsigned int,  sqrt_num_samples, , );
rtDeclareVariable(unsigned int,  rr_begin_depth, , );
rtDeclareVariable(unsigned int,  pathtrace_ray_type, , );
rtDeclareVariable(unsigned int,  pathtrace_shadow_ray_type, , );
rtDeclareVariable(int,  row, , );
rtDeclareVariable(int,  maxDepth, , );

rtBuffer<float4, 2>              output_buffer;
rtBuffer<ParallelogramLight>     lights;

rtBuffer<Photon>	photonBuffer;
rtBuffer<int>	isHitBuffer;

#define DECRESE_FACTOR 0.3

RT_PROGRAM void pathtrace_camera()
{
    size_t2 screen = output_buffer.size();
	unsigned int seed = tea<16>(screen.x*launch_index.y+launch_index.x, frame_number);
	float2 u1u2;
	u1u2.x = rnd(seed);
	u1u2.y = rnd(seed);

    float3 result = make_float3(0.0f);
	int index = screen.x*launch_index.y+launch_index.x;
	float phi = 2 * M_PI * u1u2.y;
	float theta = M_PI * 0.5f * u1u2.x;
	float r = sin(theta);
	float3 dir = make_float3(r * cos(phi), -cos(theta), r * sin(phi));
	
	int xx = frame_number / row;
	int yy = frame_number % row;
	float d = 1.f / (row - 1);

	ParallelogramLight light = lights[0];
	const float z1 = rnd(seed);
	const float z2 = rnd(seed);
	const float3 light_pos = light.corner + light.v1 * d * xx + light.v2 * d * yy;

    float3 ray_origin = light_pos;
    float3 ray_direction = dir;

	float3 firstRay_direction = ray_direction;
	float t;
    // Initialze per-ray data
    PerRayData_pathtrace prd;
    prd.result = make_float3(0.f);
    prd.attenuation = make_float3(1.f);
	prd.radiance = make_float3(0.15f);
    prd.countEmitted = true;
    prd.done = false;
	prd.seed = seed;
    prd.depth = 0;
	prd.isSpecular = 0;
	/*prd.rayPdf = 1.f / (screen.x*screen.y);*/
	prd.rayPdf = 1.f;

	for (int i = 0; i < maxDepth; i++)
		isHitBuffer[maxDepth * index + i] = 0;
    // Each iteration is a segment of the ray path.  The closest hit will
    // return new segments to be traced here.
    for(;;)
    {
		if (prd.depth >= maxDepth)
			break;
		prd.isSpecular = 0;
		ray_direction = normalize(ray_direction);
        Ray ray = make_Ray(ray_origin, ray_direction, pathtrace_ray_type, scene_epsilon, RT_DEFAULT_MAX);
        rtTrace(top_object, ray, prd);

        if(prd.done)
        {
            // We have hit the background or a luminaire
            prd.result += prd.radiance * prd.attenuation;
            break;
        }
        if(prd.depth >= rr_begin_depth)
        {
            float pcont = fmaxf(prd.attenuation);
            if(rnd(prd.seed) >= pcont)
                break;
            prd.attenuation /= pcont;
        }

		prd.result += prd.radiance * prd.attenuation;
		if (!prd.isSpecular)
			isHitBuffer[maxDepth * index + prd.depth] = 1;

		// Be careful of calculating the indices!
		photonBuffer[maxDepth * index + prd.depth].position = ray.origin + prd.tValue * ray.direction;
		photonBuffer[maxDepth * index + prd.depth].color = make_float3(prd.rayPdf * 10);
			photonBuffer[maxDepth * index + prd.depth].rayPdf = prd.rayPdf;
        prd.depth++;
		photonBuffer[maxDepth * index + prd.depth].rayDepth = prd.depth;
		


        // Update ray data for the next path segment
        ray_origin = prd.origin;
        ray_direction = prd.direction;
    }

    result += prd.result;
	seed = prd.seed;
    //
    // Update the output buffer
    //
    float3 pixel_color = result;
}


//-----------------------------------------------------------------------------
//
//  Emissive surface closest-hit
//
//-----------------------------------------------------------------------------

rtDeclareVariable(float3,        emission_color, , );

RT_PROGRAM void diffuseEmitter()
{
    current_prd.radiance = current_prd.countEmitted ? emission_color : make_float3(0.f);
    current_prd.done = true;
}


//-----------------------------------------------------------------------------
//
//  Lambertian surface closest-hit
//
//-----------------------------------------------------------------------------

rtDeclareVariable(float3,     diffuse_color, , );
rtDeclareVariable(float3,     geometric_normal, attribute geometric_normal, );
rtDeclareVariable(float3,     shading_normal,   attribute shading_normal, );
rtDeclareVariable(optix::Ray, ray,              rtCurrentRay, );
rtDeclareVariable(float,      t_hit,            rtIntersectionDistance, );
rtDeclareVariable(float, tValue, attribute tValue, );

RT_PROGRAM void diffuse()
{
    float3 world_shading_normal   = normalize( rtTransformNormal( RT_OBJECT_TO_WORLD, shading_normal ) );
    float3 world_geometric_normal = normalize( rtTransformNormal( RT_OBJECT_TO_WORLD, geometric_normal ) );
    float3 ffnormal = faceforward( world_shading_normal, -ray.direction, world_geometric_normal );

    float3 hitpoint = ray.origin + t_hit * ray.direction;

    //
    // Generate a reflection ray.  This will be traced back in ray-gen.
    //
    current_prd.origin = hitpoint;

    float z1=rnd(current_prd.seed);
    float z2=rnd(current_prd.seed);
    float3 p;
    cosine_sample_hemisphere(z1, z2, p);
    optix::Onb onb( ffnormal );
    onb.inverse_transform( p );
    current_prd.direction = p;

    // NOTE: f/pdf = 1 since we are perfectly importance sampling lambertian
    // with cosine density.
    current_prd.attenuation = current_prd.attenuation * diffuse_color;
    current_prd.countEmitted = false;

    //
    // Next event estimation (compute direct lighting).
    //
    unsigned int num_lights = lights.size();
    float3 result = make_float3(0.0f);
    for(int i = 0; i < num_lights; ++i)
    {
        // Choose random point on light
        ParallelogramLight light = lights[i];
        const float z1 = rnd(current_prd.seed);
        const float z2 = rnd(current_prd.seed);
        const float3 light_pos = light.corner + light.v1 * z1 + light.v2 * z2;

        // Calculate properties of light sample (for area based pdf)
        const float  Ldist = length(light_pos - hitpoint);
        const float3 L     = normalize(light_pos - hitpoint);
        const float  nDl   = dot( ffnormal, L );
        const float  LnDl  = dot( light.normal, L );

        // cast shadow ray
        if ( nDl > 0.0f && LnDl > 0.0f )
        {
            PerRayData_pathtrace_shadow shadow_prd;
            shadow_prd.inShadow = false;
            // Note: bias both ends of the shadow ray, in case the light is also present as geometry in the scene.
            Ray shadow_ray = make_Ray( hitpoint, L, pathtrace_shadow_ray_type, scene_epsilon, Ldist - scene_epsilon );
            rtTrace(top_object, shadow_ray, shadow_prd);

			// do not calculate shadow in pre-pass, calculate in the second-pass


            if(!shadow_prd.inShadow)
            {
                const float A = length(cross(light.v1, light.v2));
                // convert area based pdf to solid angle
                const float weight = nDl * LnDl * A / (M_PIf * Ldist * Ldist);
                result += light.emission * weight;
            }

        }
    }
	current_prd.radiance *= DECRESE_FACTOR;
	current_prd.tValue = tValue;
	current_prd.rayPdf *= 1.f / (2.f * M_PIf);
	float brdfPdf = M_1_PIf;
}

rtDeclareVariable(float3, world_normal, attribute world_normal, );
RT_PROGRAM void specular()
{
	float3 ffnormal = faceforward( world_normal, -ray.direction, world_normal );
	float3 hitpoint = ray.origin + t_hit * ray.direction;
	current_prd.origin = hitpoint;
	float3 R = reflect(ray.direction, ffnormal);
	current_prd.direction = R;
	current_prd.attenuation = current_prd.attenuation;
	current_prd.countEmitted = true;
	unsigned int num_lights = lights.size();
	float3 result = make_float3(0.0f);
	current_prd.radiance = current_prd.radiance;
	current_prd.tValue = tValue;
	current_prd.isSpecular = 1;
	current_prd.rayPdf *= 1.f;
	float brdfPdf = 1.f;
}

//-----------------------------------------------------------------------------
//
//  Shadow any-hit
//
//-----------------------------------------------------------------------------

rtDeclareVariable(PerRayData_pathtrace_shadow, current_prd_shadow, rtPayload, );

RT_PROGRAM void shadow()
{
    current_prd_shadow.inShadow = true;
    rtTerminateRay();
}


//-----------------------------------------------------------------------------
//
//  Exception program
//
//-----------------------------------------------------------------------------

RT_PROGRAM void exception()
{
    output_buffer[launch_index] = make_float4(bad_color, 1.0f);
}


//-----------------------------------------------------------------------------
//
//  Miss program
//
//-----------------------------------------------------------------------------

rtDeclareVariable(float3, bg_color, , );

RT_PROGRAM void miss()
{
    current_prd.radiance = bg_color;
    current_prd.done = true;
}

RT_PROGRAM void glass_closest_hit_radiance()
{
	float n1 = 1.0f, n2 = 1.5f;
    float3 hitpoint = ray.origin + t_hit * ray.direction;
	
	float3 d = normalize(ray.direction);

	float cosTheta = dot(ray.direction, world_normal);
	float eta = n2 / n1;
	float3 realNormal;

	if (cosTheta > 0.0f)
	{
		realNormal = -world_normal;		
	}
	else
	{
		realNormal = world_normal;
		//eta = n1 / n2;
		cosTheta = -cosTheta;
	}
	
	unsigned int seed = t_hit * frame_number;
	float u01 = rnd(seed);

	if (u01 < (n2 - n1) / (n2 + n1) * (n2 - n1) / (n2 + n1) + (1 - (n2 - n1) / (n2 + n1) * (n2 - n1) / (n2 + n1)) * pow(1 - cosTheta, 5))
	{
		current_prd.direction = reflect(ray.direction, realNormal);
	}
	else
	{
		refract(current_prd.direction, ray.direction, world_normal, eta);
	}

	current_prd.origin = hitpoint;
    current_prd.attenuation = current_prd.attenuation;
    current_prd.countEmitted = true;
	
    float3 result = make_float3(0.0f);
	current_prd.radiance *= DECRESE_FACTOR;
	current_prd.tValue = tValue;
	current_prd.isSpecular = 1;
	current_prd.rayPdf *= 1.f;
	float brdfPdf = 1.f;
}
