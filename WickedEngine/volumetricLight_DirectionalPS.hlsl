#define DISABLE_TRANSPARENT_SHADOWMAP
#define DISABLE_SOFT_SHADOWS
#include "deferredLightHF.hlsli"
#include "fogHF.hlsli"

float4 main(VertexToPixel input) : SV_TARGET
{
	ShaderEntityType light = EntityArray[(uint)g_xColor.x];

	if (!light.IsCastingShadow())
	{
		// Dirlight volume has no meaning without shadows!!
		return 0;
	}

	float2 ScreenCoord = input.pos2D.xy / input.pos2D.w * float2(0.5f, -0.5f) + 0.5f;
	float depth = max(input.pos.z, texture_depth.SampleLevel(sampler_linear_clamp, ScreenCoord, 0));
	float3 P = getPosition(ScreenCoord, depth);
	float3 V = g_xCamera_CamPos - P;
	float cameraDistance = length(V);
	V /= cameraDistance;

	float marchedDistance = 0;
	float3 accumulation = 0;

	const float3 L = light.directionWS;

	float3 rayEnd = g_xCamera_CamPos;

	const uint sampleCount = 128;
	const float stepSize = length(P - rayEnd) / sampleCount;

	// Perform ray marching to integrate light volume along view ray:
	[loop]
	for (uint i = 0; i < sampleCount; ++i)
	{
		bool valid = false;

		for (uint cascade = 0; cascade < g_xFrame_ShadowCascadeCount; ++cascade)
		{
			float3 ShPos = mul(float4(P, 1), MatrixArray[light.GetShadowMatrixIndex() + cascade]).xyz; // ortho matrix, no divide by .w
			float3 ShTex = ShPos.xyz * float3(0.5f, -0.5f, 0.5f) + 0.5f;

			[branch]if (is_saturated(ShTex))
			{
				float3 attenuation = shadowCascade(ShPos, ShTex.xy, light.shadowKernel, light.shadowBias, light.GetShadowMapIndex() + cascade);

				attenuation *= GetFog(cameraDistance - marchedDistance);

				accumulation += attenuation;

				marchedDistance += stepSize;
				P = P + V * stepSize;

				valid = true;
				break;
			}
		}

		if (!valid)
		{
			break;
		}
	}

	accumulation /= sampleCount;

	return max(0, float4(accumulation * light.GetColor().rgb * light.energy, 1));
}