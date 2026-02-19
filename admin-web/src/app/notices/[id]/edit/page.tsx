'use client';

import { useParams } from 'next/navigation';
import NoticeForm from '../../NoticeForm';

export default function EditNoticePage() {
    const params = useParams();
    const noticeId = params.id as string;

    return <NoticeForm noticeId={noticeId} />;
}
