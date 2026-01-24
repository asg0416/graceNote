import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/providers/data_providers.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/utils/snack_bar_util.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isLoading = false;
  final _picker = ImagePicker();

  Future<void> _pickAndUploadImage() async {
    final profile = ref.read(userProfileProvider).value;
    if (profile == null) return;

    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 75,
    );

    if (image == null) return;

    setState(() => _isLoading = true);

    try {
      final bytes = await image.readAsBytes();
      
      // Handle file extension and MIME type correctly for Web/Mobile
      String? mimeType = image.mimeType;
      String fileExt = 'jpg'; // Default extension
      
      if (mimeType != null && mimeType.contains('/')) {
        fileExt = mimeType.split('/').last;
      } else {
        // Fallback for cases where mimeType is null (e.g. some web platforms)
        final path = image.path.toLowerCase();
        if (path.contains('.png')) {
          fileExt = 'png';
          mimeType = 'image/png';
        } else if (path.contains('.gif')) {
          fileExt = 'gif';
          mimeType = 'image/gif';
        } else if (path.contains('.heic')) {
          fileExt = 'heic';
          mimeType = 'image/heic';
        } else {
          fileExt = 'jpg';
          mimeType = 'image/jpeg';
        }
      }

      final fileName = '${profile.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      const bucketName = 'avatars';

      // 1. Upload to Storage using bytes
      await Supabase.instance.client.storage
          .from(bucketName)
          .uploadBinary(fileName, bytes, fileOptions: FileOptions(contentType: mimeType));

      // 2. Get Public URL
      final imageUrl = Supabase.instance.client.storage
          .from(bucketName)
          .getPublicUrl(fileName);

      // 3. Update Profile Table
      await Supabase.instance.client
          .from('profiles')
          .update({'avatar_url': imageUrl})
          .eq('id', profile.id);

      if (mounted) {
        ref.invalidate(userProfileProvider);
        SnackBarUtil.showSnackBar(context, message: '프로필 사진이 업데이트되었습니다.');
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showSnackBar(
          context,
          message: '업로드에 실패했습니다.',
          isError: true,
          technicalDetails: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _changePassword() async {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null) return;

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('비밀번호 재설정'),
            content: Text('$email 주소로 비밀번호 재설정 링크를 보냈습니다. 이메일을 확인해 주세요.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('확인')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showSnackBar(
          context,
          message: '요청에 실패했습니다.',
          isError: true,
          technicalDetails: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('개인정보 관리', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textMain),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: profileAsync.when(
        data: (profile) {
          if (profile == null) return const Center(child: Text('프로필 정보를 불러올 수 없습니다.'));
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _buildAvatarSection(profile),
                const SizedBox(height: 40),
                _buildInfoSection(profile),
                const SizedBox(height: 32),
                _buildAccountSection(),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류 발생: $e')),
      ),
    );
  }

  Widget _buildAvatarSection(dynamic profile) {
    return Center(
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryIndigo.withOpacity(0.15),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(6.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(60),
                child: _isLoading 
                  ? const Center(child: CircularProgressIndicator())
                  : (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty)
                    ? Image.network(profile.avatarUrl!, fit: BoxFit.cover)
                    : Image.asset('assets/images/avatar.png', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 60, color: AppTheme.divider)),
              ),
            ),
          ),
          InkWell(
            onTap: _pickAndUploadImage,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryIndigo,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(dynamic profile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 8, bottom: 12),
          child: Text('기본 정보', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppTheme.textSub)),
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 20, offset: const Offset(0, 10)),
            ],
          ),
          child: Column(
            children: [
              _buildInfoRow('이름', profile.fullName),
              const Divider(height: 32, color: AppTheme.divider),
              _buildInfoRow('연락처', profile.phone ?? '등록된 번호 없음'),
              const Divider(height: 32, color: AppTheme.divider),
              _buildInfoRow('생년월일', profile.birthDate ?? '미설정'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 8, bottom: 12),
          child: Text('계정 관리', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppTheme.textSub)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 20, offset: const Offset(0, 10)),
            ],
          ),
          child: ListTile(
            onTap: _changePassword,
            leading: const Icon(Icons.lock_reset_rounded, color: AppTheme.primaryIndigo),
            title: const Text('비밀번호 설정 변경', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('이메일로 재설정 링크를 받습니다.', style: TextStyle(fontSize: 12, color: AppTheme.textSub)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppTheme.divider),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textSub)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain)),
      ],
    );
  }
}
