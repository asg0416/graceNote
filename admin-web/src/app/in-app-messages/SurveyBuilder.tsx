'use client';

import { Star, Plus, Trash2, X } from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) { return twMerge(clsx(inputs)); }

export interface SurveyQuestion {
  id: string;
  type: 'star_rating' | 'radio' | 'checkbox' | 'text';
  text: string;
  required: boolean;
  options: string[];
}

const TYPE_LABELS: Record<SurveyQuestion['type'], string> = {
  star_rating: '별점',
  radio: '단일 선택',
  checkbox: '다중 선택',
  text: '주관식',
};

function newQuestion(): SurveyQuestion {
  return {
    id: crypto.randomUUID(),
    type: 'star_rating',
    text: '',
    required: false,
    options: [],
  };
}

interface Props {
  questions: SurveyQuestion[];
  onChange: (questions: SurveyQuestion[]) => void;
}

export default function SurveyBuilder({ questions, onChange }: Props) {
  const update = (idx: number, patch: Partial<SurveyQuestion>) => {
    const next = questions.map((q, i) => (i === idx ? { ...q, ...patch } : q));
    onChange(next);
  };

  const addQuestion = () => {
    if (questions.length >= 6) return;
    onChange([...questions, newQuestion()]);
  };

  const removeQuestion = (idx: number) => {
    onChange(questions.filter((_, i) => i !== idx));
  };

  const addOption = (idx: number) => {
    const q = questions[idx];
    if (q.options.length >= 8) return;
    update(idx, { options: [...q.options, ''] });
  };

  const updateOption = (qIdx: number, oIdx: number, val: string) => {
    const opts = questions[qIdx].options.map((o, i) => (i === oIdx ? val : o));
    update(qIdx, { options: opts });
  };

  const removeOption = (qIdx: number, oIdx: number) => {
    const opts = questions[qIdx].options.filter((_, i) => i !== oIdx);
    update(qIdx, { options: opts });
  };

  const changeType = (idx: number, type: SurveyQuestion['type']) => {
    const patch: Partial<SurveyQuestion> = { type };
    if (type === 'radio' || type === 'checkbox') {
      patch.options = questions[idx].options.length >= 2
        ? questions[idx].options
        : ['', ''];
    } else {
      patch.options = [];
    }
    update(idx, patch);
  };

  return (
    <div className="space-y-3">
      {questions.map((q, idx) => (
        <div
          key={q.id}
          className="border border-slate-200 dark:border-slate-700 rounded-2xl p-4 bg-white dark:bg-slate-900/50 space-y-3"
        >
          {/* 질문 헤더 */}
          <div className="flex items-center gap-2">
            <span className="text-xs font-black text-slate-400 w-6 shrink-0">
              Q{idx + 1}
            </span>
            <select
              value={q.type}
              onChange={e => changeType(idx, e.target.value as SurveyQuestion['type'])}
              className="text-xs font-bold bg-slate-100 dark:bg-slate-800 border-0 rounded-lg px-2.5 py-1.5 text-slate-700 dark:text-slate-200 focus:ring-2 focus:ring-violet-500/30 focus:outline-none"
            >
              {(Object.keys(TYPE_LABELS) as SurveyQuestion['type'][]).map(t => (
                <option key={t} value={t}>{TYPE_LABELS[t]}</option>
              ))}
            </select>
            <div className="flex-1" />
            <button
              type="button"
              onClick={() => removeQuestion(idx)}
              className="p-1.5 text-slate-300 hover:text-red-400 transition-colors rounded-lg"
            >
              <Trash2 size={14} />
            </button>
          </div>

          {/* 질문 텍스트 */}
          <input
            type="text"
            value={q.text}
            onChange={e => update(idx, { text: e.target.value.slice(0, 200) })}
            placeholder="질문 내용을 입력하세요"
            maxLength={200}
            className="w-full text-sm bg-slate-50 dark:bg-slate-800/50 border border-slate-200 dark:border-slate-700 rounded-xl px-3 py-2 focus:outline-none focus:ring-2 focus:ring-violet-500/30 text-slate-800 dark:text-slate-100 placeholder-slate-300"
          />
          <div className="text-right text-[10px] text-slate-300 -mt-1">
            {q.text.length}/200
          </div>

          {/* 타입별 추가 UI */}
          {q.type === 'star_rating' && (
            <div className="flex gap-1 px-1">
              {[1, 2, 3, 4, 5].map(i => (
                <Star key={i} size={20} className="text-amber-300 fill-amber-300" />
              ))}
              <span className="text-xs text-slate-300 ml-2 self-center">미리보기 (편집 불가)</span>
            </div>
          )}

          {(q.type === 'radio' || q.type === 'checkbox') && (
            <div className="space-y-2">
              {q.options.map((opt, oIdx) => (
                <div key={oIdx} className="flex items-center gap-2">
                  <div className={cn(
                    "w-3.5 h-3.5 border-2 border-slate-300 shrink-0",
                    q.type === 'radio' ? 'rounded-full' : 'rounded-sm'
                  )} />
                  <input
                    type="text"
                    value={opt}
                    onChange={e => updateOption(idx, oIdx, e.target.value.slice(0, 50))}
                    placeholder={`옵션 ${oIdx + 1}`}
                    maxLength={50}
                    className="flex-1 text-sm bg-slate-50 dark:bg-slate-800/50 border border-slate-200 dark:border-slate-700 rounded-lg px-2.5 py-1.5 focus:outline-none focus:ring-2 focus:ring-violet-500/30 text-slate-800 dark:text-slate-100 placeholder-slate-300"
                  />
                  {q.options.length > 2 && (
                    <button
                      type="button"
                      onClick={() => removeOption(idx, oIdx)}
                      className="p-1 text-slate-300 hover:text-red-400 transition-colors"
                    >
                      <X size={13} />
                    </button>
                  )}
                </div>
              ))}
              {q.options.length < 8 && (
                <button
                  type="button"
                  onClick={() => addOption(idx)}
                  className="text-xs text-violet-500 hover:text-violet-700 font-bold flex items-center gap-1 pl-5 mt-1"
                >
                  <Plus size={12} /> 옵션 추가
                </button>
              )}
            </div>
          )}

          {q.type === 'text' && (
            <div className="bg-slate-50 dark:bg-slate-800/50 border border-slate-200 dark:border-slate-700 rounded-xl px-3 py-2 text-xs text-slate-300 italic">
              주관식 텍스트 입력란 (미리보기)
            </div>
          )}

          {/* 필수 여부 */}
          <label className="flex items-center gap-2 cursor-pointer select-none">
            <input
              type="checkbox"
              checked={q.required}
              onChange={e => update(idx, { required: e.target.checked })}
              className="w-3.5 h-3.5 accent-violet-600"
            />
            <span className="text-xs text-slate-500 font-bold">필수 질문</span>
          </label>
        </div>
      ))}

      {/* 질문 추가 버튼 */}
      <button
        type="button"
        onClick={addQuestion}
        disabled={questions.length >= 6}
        className={cn(
          "w-full py-3 rounded-2xl border-2 border-dashed text-sm font-bold flex items-center justify-center gap-2 transition-all",
          questions.length >= 6
            ? "border-slate-200 dark:border-slate-800 text-slate-300 cursor-not-allowed"
            : "border-violet-200 dark:border-violet-800 text-violet-500 hover:bg-violet-50 dark:hover:bg-violet-900/20"
        )}
      >
        <Plus size={16} />
        {questions.length >= 6 ? '질문 최대 6개' : '질문 추가'}
      </button>
    </div>
  );
}
