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

        // Fallback strategy: Based on verified ListModels output for this key:
        // Try newer generation models (2.0) and latest aliases
        const modelNames = ["gemini-2.0-flash", "gemini-2.0-flash-lite", "gemini-1.5-flash", "gemini-flash-latest"];
        let lastError: any = null;

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
          2. GROUP NAME: 
             - Extract the "조" or "Group" information. 
             - IMPORTANT: If there is no specific "조" info (e.g., it's just a general member list), or if the "조" column contains department names like "예닮부", set group_name to "미정". 
             - Only set a specific group_name if it clearly indicates a small group (e.g., "1조", "현권 조").
          3. GROUP LEADERS: Look for groups or headers explicitly marked as leader (조장, 리더).
             - Create a separate object for EACH person in the header.
             - Set "role_in_group": "leader" for them.
          4. FAMILY LINKS (CRITICAL): 
             - If a couple is detected (e.g., "재홍 혜진"), Object 1 (재홍) MUST have spouse_name="혜진", and Object 2 (혜진) MUST have spouse_name="재홍".
             - If children are listed for a family, ALL adults in that family (both spouses) MUST have the same "children_info". Do not leave it null for one spouse if the other has it.
          5. INDIVIDUALIZATION: Create separate objects for each adult. 
             - For "재홍 혜진 (예봄, 예강)", Object 1: full_name="재홍", spouse_name="혜진", children_info="예봄, 예강"; Object 2: full_name="혜진", spouse_name="재홍", children_info="예봄, 예강".
          6. NOISE REMOVAL: Clean labels like "딸:", "아들:", "(A)", "성도", etc., from names.
          
          Return ONLY a clean JSON array of objects with the following keys:
          - full_name: string (The person's name)
          - role_in_group: "leader" | "member"
          - spouse_name: string or null (Mutual reference)
          - children_info: string or null (Assign to both parents)
          - group_name: string ("미정" if no clear small group)
          - phone: string (Mobile phone number, default empty)

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
