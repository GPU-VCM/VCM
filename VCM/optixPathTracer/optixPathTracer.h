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

#pragma once

#include <optixu/optixu_math_namespace.h>                                        

struct ParallelogramLight                                                        
{                                                                                
    optix::float3 corner;                                                          
    optix::float3 v1, v2;                                                          
    optix::float3 normal;                                                          
    optix::float3 emission;

	float getArea(){
		return optix::length(optix::cross(v1 / optix::dot(v1, v1), v2 / optix::dot(v2, v2)));
	}
};                                                                               

struct Photon
{
	optix::float3 position;
	optix::float3 color;
	float rayPdf;
	int rayDepth;

	Photon(){}

	Photon(const Photon &p)
	{
		position = p.position;
		color = p.color;
		rayPdf = p.rayPdf;
		rayDepth = 0;
	}
	bool operator()(const Photon &a, const Photon &b) const
	{
		return a.position.x < b.position.x;
	}
	bool operator<(const Photon &b) const
	{
		return position.x < b.position.x;
	}
};


