import { GoogleGenerativeAI } from "@google/generative-ai";
import { NextResponse } from "next/server";

export async function POST(req: Request) {
    try {
        const { prayers } = await req.json();
        if (!prayers || !Array.isArray(prayers)) {
            return NextResponse.json({ error: "Prayers array is required" }, { status: 400 });
        }

        const apiKey = process.env.GOOGLE_AI_API_KEY;
        if (!apiKey) {
            return NextResponse.json({ error: "API Key not configured" }, { status: 500 });
        }

        const genAI = new GoogleGenerativeAI(apiKey);

        // Fallback strategy: try several models that are known to work in different regions/versions
        const modelNames = [
            "gemini-2.0-flash",
            "gemini-1.5-flash",
            "gemini-1.5-flash-8b",
            "gemini-pro"
        ];

        const prompt = `
다음은 기독교 소그룹 조원들의 거친 기도제목 메모들입니다. 
각 메모를 다음 규칙에 따라 정중하고 따뜻한 기도문체(~하게 하소서, ~하기를 소망합니다 등)로 다듬어주세요:

1. 하나의 메모 안에 여러 주제가 섞여 있다면 "1. ..., 2. ..."와 같이 번호를 매겨서 정돈해주세요.
2. 내용은 왜곡하지 말고 문장만 매끄럽게 다듬으세요.
3. 각 신청자의 결과물 사이에는 [SEP]라는 구분자를 넣어주세요.
4. 추가 설명이나 인사말 없이 결과만 출력하세요.

입력 메모 리스트:
${prayers.join('\n[NEXT]\n')}
`;

        let lastError = null;
        for (const modelName of modelNames) {
            try {
                const model = genAI.getGenerativeModel({ model: modelName }, { apiVersion: "v1beta" });
                const result = await model.generateContent(prompt);
                const response = await result.response;
                const text = response.text();

                if (text) {
                    const refinedList = text
                        .split('[SEP]')
                        .map(s => s.trim())
                        .filter(s => s.length > 0);

                    return NextResponse.json({ data: refinedList });
                }
            } catch (err: any) {
                console.warn(`AI Proxy failed with ${modelName}:`, err.message);
                lastError = err;
                continue;
            }
        }

        throw lastError || new Error("All AI models failed");

    } catch (error: any) {
        console.error("AI Proxy Error:", error);
        return NextResponse.json({ error: error.message }, { status: 500 });
    }
}
