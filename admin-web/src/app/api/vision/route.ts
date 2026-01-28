import { GoogleGenerativeAI } from "@google/generative-ai";
import { NextResponse } from "next/server";

export async function POST(req: Request) {
    try {
        const { image, text: rawTextContent, mimeType = "image/png" } = await req.json();
        if (!image && !rawTextContent) {
            return NextResponse.json({ error: "Data is required" }, { status: 400 });
        }

        const apiKey = process.env.GOOGLE_AI_API_KEY;
        if (!apiKey) {
            return NextResponse.json({ error: "API Key not configured" }, { status: 500 });
        }

        const genAI = new GoogleGenerativeAI(apiKey);

        const modelNames = ["gemini-1.5-flash", "gemini-2.0-flash", "gemini-1.5-pro"];
        let lastError = null;

        for (const modelName of modelNames) {
            try {
                const model = genAI.getGenerativeModel(
                    { model: modelName },
                    { apiVersion: "v1beta" }
                );

                const prompt = `
          Extract church organization/group assignment data from this ${rawTextContent ? 'text data' : (mimeType.includes('pdf') ? 'document' : 'image')}.
          
          CRITICAL INSTRUCTIONS:
          1. STRUCTURE LOGIC: If the data is text/CSV, first identify the headers. Use column positions and labels to determine meaning.
          2. GROUP LEADERS: Look for group headers (usually ending in "조", e.g., "현권 영미 조" or "1조"). The names in these headers or explicitly marked as leader are the Group Leaders. 
             - Create a separate object for EACH person in the header.
             - Set "role_in_group": "leader" for them.
          3. INDIVIDUALIZATION: If a line or cell contains multiple adults (e.g., "재홍 혜진 (예봄, 예강)"), create TWO separate objects:
             - Object 1: full_name="재홍", spouse_name="혜진", children_info="예봄, 예강", role_in_group="member"
             - Object 2: full_name="혜진", spouse_name="재홍", children_info="예봄, 예강", role_in_group="member"
          4. FAMILY LINKS: When splitting a couple, ensure they cross-reference each other in the "spouse_name" field.
          5. NOISE REMOVAL: Clean labels like "딸:", "아들:", "(A)", "성도", etc., from names.
          
          Return ONLY a clean JSON array of objects with the following keys:
          - full_name: string (The person's name)
          - role_in_group: "leader" | "member"
          - spouse_name: string or null
          - children_info: string or null
          - group_name: string (The name of the group they belong to)
          - phone: string (Mobile phone number if exists, default empty)

          Do not include any other text. No markdown decorators. Just the raw JSON.
        `;

                const content: any[] = [prompt];
                if (image) {
                    content.push({
                        inlineData: {
                            data: image.split(",")[1] || image,
                            mimeType: mimeType,
                        },
                    });
                } else if (rawTextContent) {
                    content.push(rawTextContent);
                }

                const result = await model.generateContent(content);

                const response = await result.response;
                const text = response.text();

                // Robust JSON extraction
                const jsonMatch = text.match(/\[[\s\S]*\]/);
                if (jsonMatch) {
                    const data = JSON.parse(jsonMatch[0]);
                    return NextResponse.json({ data });
                }
            } catch (err: any) {
                console.warn(`Failed with model ${modelName}:`, err.message);
                lastError = err;

                // If it's a quota error, we might want to tell the user directly later
                if (err.message?.includes("429") || err.message?.includes("quota")) {
                    continue; // Try next one, maybe it has separate quota
                }
                continue;
            }
        }

        if (lastError?.message?.includes("429")) {
            return NextResponse.json({
                error: "Google AI API 사용량이 초과되었습니다 (429 Quota Exceeded). 잠시 후 다시 시도하시거나, 아래 '직접 텍스트 붙여넣기' 기능을 이용해 주세요.",
                details: lastError.message
            }, { status: 429 });
        }

        throw lastError || new Error("모든 AI 모델 호출에 실패했습니다.");
    } catch (error: any) {
        console.error("Vision API Error:", error);
        return NextResponse.json({ error: error.message }, { status: 500 });
    }
}
