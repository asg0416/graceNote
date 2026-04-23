import IamForm from '../../IamForm';

interface Props {
    params: Promise<{ id: string }>;
}

export default async function EditInAppMessagePage({ params }: Props) {
    const { id } = await params;
    return <IamForm messageId={id} />;
}
