Shader "Custom/DepthTexture" {
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
                
                return EncodeFloatRGBA(depth);
            }
            
            ENDCG
        }
        
    }
    FallBack "Diffuse"
}