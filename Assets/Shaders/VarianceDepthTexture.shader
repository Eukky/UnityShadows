Shader "Custom/VarianceDepthTexture" {
    SubShader {
        Tags { "RenderType"="Opaque" }
        Pass 
        {
            Cull Front 
            CGPROGRAM
            
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct a2v
            {
                float4 vertex : POSITION;
            };

            struct v2f
            {
                float4 position : SV_POSITION;
            };

            v2f vert(a2v v)
            {
                v2f o;
                o.position = UnityObjectToClipPos(v.vertex);
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float depth = i.position.z / i.position.w;
               
                #if defined(SHADER_TARGET_GLSL)
                    depth = depth * 0.5 + 0.5;
                #elif defined(UNITY_REVERSED_Z)
                    depth = 1 - depth;
                #endif
                
                float depth2 = depth * depth;
                float depth3 = depth2 * depth;
                float depth4 = depth3 * depth;
                // float dx = ddx(depth);
                // float dy = ddx(depth);
                // depth2 += 0.25 * (dx * dx + dy * dy);
                //
                // float2 ed1 = EncodeFloatRG(depth);
                // float2 ed2 = EncodeFloatRG(depth2);
                // return fixed4(ed1, ed2);
                return float4(depth, depth2, depth3, depth4);
            }
            
            ENDCG
        }
        
    }
    FallBack "Diffuse"
}