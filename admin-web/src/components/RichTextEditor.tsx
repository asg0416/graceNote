'use client';

import { useEffect } from 'react';
import { useEditor, EditorContent } from '@tiptap/react';
import StarterKit from '@tiptap/starter-kit';
import Underline from '@tiptap/extension-underline';
import TaskList from '@tiptap/extension-task-list';
import TaskItem from '@tiptap/extension-task-item';
import { Color } from '@tiptap/extension-color';
import { TextStyle } from '@tiptap/extension-text-style';
import Placeholder from '@tiptap/extension-placeholder';
import {
    Bold,
    Italic,
    Underline as UnderlineIcon,
    Strikethrough,
    List,
    ListOrdered,
    CheckSquare,
    Palette,
    Heading1,
    Heading2,
    Heading3,
    Undo,
    Redo,
    Type
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
    return twMerge(clsx(inputs));
}

interface RichTextEditorProps {
    content: string;
    onChange: (content: string) => void;
    editable?: boolean;
    placeholder?: string;
}

const MenuButton = ({
    onClick,
    isActive = false,
    disabled = false,
    children,
    title
}: {
    onClick: () => void;
    isActive?: boolean;
    disabled?: boolean;
    children: React.ReactNode;
    title?: string;
}) => (
    <button
        onClick={(e) => {
            e.preventDefault();
            onClick();
        }}
        disabled={disabled}
        title={title}
        className={cn(
            "p-2 rounded-lg transition-all",
            isActive
                ? "bg-indigo-600 text-white shadow-sm"
                : "text-slate-500 hover:bg-slate-100 dark:hover:bg-slate-800"
        )}
    >
        {children}
    </button>
);

export default function RichTextEditor({ content, onChange, editable = true, placeholder = '여기에 메모를 입력하세요...' }: RichTextEditorProps) {
    const editor = useEditor({
        extensions: [
            StarterKit.configure({
                bulletList: {
                    keepMarks: true,
                    keepAttributes: false,
                },
                orderedList: {
                    keepMarks: true,
                    keepAttributes: false,
                },
            }),
            Underline,
            TextStyle,
            Color,
            TaskList,
            TaskItem.configure({
                nested: true,
            }),
            Placeholder.configure({
                placeholder: placeholder,
                emptyEditorClass: 'is-editor-empty',
            }),
        ],
        content: content,
        editable: editable,
        immediatelyRender: false,
        onUpdate: ({ editor }) => {
            onChange(editor.getHTML());
        },
        editorProps: {
            attributes: {
                class: cn(
                    'prose prose-sm dark:prose-invert max-w-none focus:outline-none leading-relaxed transition-all',
                    editable ? 'min-h-[200px] p-6 text-slate-700 dark:text-slate-200 font-bold' : 'text-slate-700 dark:text-slate-200 font-bold'
                ),
            },
        },
    });

    // Sync content from prop if it changes externally
    useEffect(() => {
        if (editor && content !== editor.getHTML()) {
            // Only update if content is different to avoid cursor flickering
            // And especially if it's the first load or external update
            editor.commands.setContent(content);
        }
    }, [content, editor]);

    // Important: Update editor editable state when prop changes
    if (editor && editor.isEditable !== editable) {
        editor.setEditable(editable);
    }

    if (!editor) {
        return null;
    }

    return (
        <div className={cn(
            "w-full overflow-hidden transition-all",
            editable
                ? "border border-slate-200 dark:border-slate-800 rounded-[32px] bg-white dark:bg-slate-900/40 focus-within:ring-4 focus-within:ring-indigo-500/5 shadow-sm"
                : "bg-transparent"
        )}>
            {editable && (
                <div className="p-3 border-b border-slate-100 dark:border-slate-800 flex flex-wrap gap-1.5 bg-slate-50/50 dark:bg-slate-900/60 sticky top-0 z-10 backdrop-blur-md rounded-t-[31px]">
                    <div className="flex items-center gap-1 pr-2 border-r border-slate-200 dark:border-slate-800">
                        <MenuButton
                            onClick={() => editor.chain().focus().undo().run()}
                            disabled={!editor.can().undo()}
                            title="Undo"
                        >
                            <Undo className="w-4 h-4" />
                        </MenuButton>
                        <MenuButton
                            onClick={() => editor.chain().focus().redo().run()}
                            disabled={!editor.can().redo()}
                            title="Redo"
                        >
                            <Redo className="w-4 h-4" />
                        </MenuButton>
                    </div>

                    <div className="flex items-center gap-1 px-2 border-r border-slate-200 dark:border-slate-800">
                        <MenuButton
                            onClick={() => editor.chain().focus().toggleHeading({ level: 1 }).run()}
                            isActive={editor.isActive('heading', { level: 1 })}
                            title="Heading 1"
                        >
                            <Heading1 className="w-4 h-4" />
                        </MenuButton>
                        <MenuButton
                            onClick={() => editor.chain().focus().toggleHeading({ level: 2 }).run()}
                            isActive={editor.isActive('heading', { level: 2 })}
                            title="Heading 2"
                        >
                            <Heading2 className="w-4 h-4" />
                        </MenuButton>
                        <MenuButton
                            onClick={() => editor.chain().focus().toggleHeading({ level: 3 }).run()}
                            isActive={editor.isActive('heading', { level: 3 })}
                            title="Heading 3"
                        >
                            <Heading3 className="w-4 h-4" />
                        </MenuButton>
                    </div>

                    <div className="flex items-center gap-1 px-2 border-r border-slate-200 dark:border-slate-800">
                        <MenuButton
                            onClick={() => editor.chain().focus().toggleBold().run()}
                            isActive={editor.isActive('bold')}
                            title="Bold"
                        >
                            <Bold className="w-4 h-4" />
                        </MenuButton>
                        <MenuButton
                            onClick={() => editor.chain().focus().toggleItalic().run()}
                            isActive={editor.isActive('italic')}
                            title="Italic"
                        >
                            <Italic className="w-4 h-4" />
                        </MenuButton>
                        <MenuButton
                            onClick={() => editor.chain().focus().toggleUnderline().run()}
                            isActive={editor.isActive('underline')}
                            title="Underline"
                        >
                            <UnderlineIcon className="w-4 h-4" />
                        </MenuButton>
                        <MenuButton
                            onClick={() => editor.chain().focus().toggleStrike().run()}
                            isActive={editor.isActive('strike')}
                            title="Strikethrough"
                        >
                            <Strikethrough className="w-4 h-4" />
                        </MenuButton>
                    </div>

                    <div className="flex items-center gap-1 px-2 border-r border-slate-200 dark:border-slate-800">
                        <MenuButton
                            onClick={() => editor.chain().focus().toggleBulletList().run()}
                            isActive={editor.isActive('bulletList')}
                            title="Bullet List"
                        >
                            <List className="w-4 h-4" />
                        </MenuButton>
                        <MenuButton
                            onClick={() => editor.chain().focus().toggleOrderedList().run()}
                            isActive={editor.isActive('orderedList')}
                            title="Ordered List"
                        >
                            <ListOrdered className="w-4 h-4" />
                        </MenuButton>
                        <MenuButton
                            onClick={() => editor.chain().focus().toggleTaskList().run()}
                            isActive={editor.isActive('taskList')}
                            title="Task List"
                        >
                            <CheckSquare className="w-4 h-4" />
                        </MenuButton>
                    </div>

                    <div className="flex items-center gap-4 px-2">
                        <div className="flex items-center gap-2 group/color">
                            <Palette className="w-4 h-4 text-slate-400 group-hover/color:text-indigo-500 transition-colors" />
                            <input
                                type="color"
                                onInput={(event) => {
                                    editor.chain().focus().setColor((event.target as HTMLInputElement).value).run();
                                }}
                                value={editor.getAttributes('textStyle').color || '#000000'}
                                className="w-6 h-6 rounded-md cursor-pointer border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 p-0.5 overflow-hidden"
                                title="Text Color"
                            />
                        </div>
                    </div>
                </div>
            )}
            <div
                className={cn(
                    "relative",
                    !editable && "bg-slate-50/50 dark:bg-slate-900/20 p-8 rounded-[32px] border border-slate-100 dark:border-slate-800/40"
                )}
            >
                {!editable && !content && (
                    <p className="text-sm font-bold text-slate-400 dark:text-slate-500 italic">
                        {placeholder}
                    </p>
                )}
                {(editable || content) && <EditorContent editor={editor} />}
                <style jsx global>{`
                    .ProseMirror p.is-editor-empty:first-child::before {
                        content: attr(data-placeholder);
                        float: left;
                        color: #adb5bd;
                        pointer-events: none;
                        height: 0;
                        font-style: italic;
                        font-weight: 500;
                    }
                    .prose ul[data-type="taskList"] {
                        list-style: none;
                        padding: 0;
                    }
                    .prose ul[data-type="taskList"] li {
                        display: flex;
                        gap: 0.75rem;
                        align-items: flex-start;
                        margin-bottom: 0.5rem;
                    }
                    .prose ul[data-type="taskList"] li > label {
                        flex: 0 0 auto;
                        user-select: none;
                        margin-top: 0.25rem;
                    }
                    .prose ul[data-type="taskList"] li > label input[type="checkbox"] {
                        cursor: pointer;
                        width: 1.25rem;
                        height: 1.25rem;
                        accent-color: #4f46e5;
                        border-radius: 0.375rem;
                    }
                    .prose ul[data-type="taskList"] li > div {
                        flex: 1 1 auto;
                    }
                    .prose ul[data-type="taskList"] li[data-checked="true"] > div {
                        text-decoration: line-through;
                        opacity: 0.5;
                    }
                    .ProseMirror:focus {
                        outline: none;
                    }
                `}</style>
            </div>
        </div>
    );
}
