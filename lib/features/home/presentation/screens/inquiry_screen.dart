import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
// import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
// import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart'; // Add for kIsWeb
import 'package:flutter/services.dart'; // Add for Uint8List if needed

import '../../../../core/utils/snack_bar_util.dart';
import '../../../../core/providers/data_providers.dart';

class InquiryScreen extends ConsumerStatefulWidget {
  const InquiryScreen({super.key});

  @override
  ConsumerState<InquiryScreen> createState() => _InquiryScreenState();
}

class _InquiryScreenState extends ConsumerState<InquiryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  String _category = 'question';
  String _historyFilter = 'all'; // 'all', 'question', 'bug', 'suggestion'
  bool _isSubmitting = false;
  late Stream<List<Map<String, dynamic>>> _inquiriesStream;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      _inquiriesStream = Supabase.instance.client
          .from('inquiries')
          .stream(primaryKey: ['id'])
          .eq('user_id', user.id)
          .order('created_at', ascending: false);
    }
  }

  final List<XFile> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_selectedImages.length >= 5) {
      if (mounted) SnackBarUtil.showSnackBar(context, message: '이미지는 최대 5장까지 첨부할 수 있습니다.', isError: true);
      return;
    }

    try {
      // Pick with compression params directly (works on Web & Mobile)
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 70, // Reduce quality for web stability
      );
      
      if (image == null) return;
      setState(() => _selectedImages.add(image));
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) SnackBarUtil.showSnackBar(context, message: '이미지 선택 중 오류가 발생했습니다.', isError: true);
    }
  }

  // Removed _compressImage as we use ImagePicker params now for better compatibility

  Future<List<String>> _uploadImages(String userId) async {
    List<String> urls = [];
    for (var image in _selectedImages) {
      try {
        final fileName = '${userId}/${DateTime.now().millisecondsSinceEpoch}_${p.basename(image.path)}';
        final storageRef = Supabase.instance.client.storage.from('inquiry_images');
        if (kIsWeb) {
          final bytes = await image.readAsBytes();
          await storageRef.uploadBinary(fileName, bytes);
        } else {
          await storageRef.upload(fileName, File(image.path));
        }
        final imageUrl = Supabase.instance.client.storage.from('inquiry_images').getPublicUrl(fileName);
        urls.add(imageUrl);
      } catch (e) {
        debugPrint('Upload error: $e');
      }
    }
    return urls;
  }

  Future<void> _submitInquiry() async {
    if (_titleController.text.isEmpty || _contentController.text.isEmpty) {
      SnackBarUtil.showSnackBar(context, message: '제목과 내용을 입력해 주세요.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Get user profile for church_id
      final profile = ref.read(userProfileProvider).value;
      final churchId = profile?.churchId;

      final imageUrls = await _uploadImages(user.id);

      await Supabase.instance.client.from('inquiries').insert({
        'user_id': user.id,
        'church_id': churchId,
        'title': _titleController.text,
        'content': _contentController.text,
        'category': _category,
        'status': 'pending',
        'images': imageUrls,
      });

      if (mounted) {
        SnackBarUtil.showSnackBar(context, message: '문의가 접수되었습니다.');
        _titleController.clear();
        _contentController.clear();
        _selectedImages.clear();
        _tabController.animateTo(1); // Move to history tab
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showSnackBar(
          context,
          message: '제출에 실패했습니다.',
          isError: true,
          technicalDetails: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final _unreadInquiryCount = ref.watch(unreadInquiryCountProvider).value ?? 0;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('문의하기 및 Q&A', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textMain),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryIndigo,
          unselectedLabelColor: AppTheme.textSub,
          indicatorColor: AppTheme.primaryIndigo,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          tabs: [
            const Tab(text: '문의하기'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('문의 내역'),
                  if (_unreadInquiryCount > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInquiryForm(),
          _buildInquiryHistory(),
        ],
      ),
    );
  }

  Widget _buildInquiryForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('어떤 점이 궁금하신가요?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.textMain)),
          const SizedBox(height: 8),
          const Text('내용을 남겨주시면 관리자가 확인 후 답변해 드립니다.', style: TextStyle(color: AppTheme.textSub, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          _buildLabel('카테고리'),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildCategoryChip('질문', 'question'),
              const SizedBox(width: 8),
              _buildCategoryChip('버그/오류', 'bug'),
              const SizedBox(width: 8),
              _buildCategoryChip('건의사항', 'suggestion'),
            ],
          ),
          const SizedBox(height: 24),
          _buildLabel('제목'),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            decoration: _buildInputDecoration('제목을 입력하세요'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          _buildLabel('상세 내용'),
          const SizedBox(height: 12),
          TextField(
            controller: _contentController,
            maxLines: 8,
            decoration: _buildInputDecoration('최대한 자세히 적어주시면 빠른 처리에 도움이 됩니다.'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          _buildLabel('이미지 첨부 (${_selectedImages.length}/5)'),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                InkWell(
                  onTap: _pickImage,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: const Icon(Icons.add_photo_alternate_rounded, color: AppTheme.textSub),
                  ),
                ),
                const SizedBox(width: 12),
                ..._selectedImages.asMap().entries.map((entry) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.divider),
                          image: DecorationImage(
                            image: kIsWeb 
                                ? NetworkImage(entry.value.path) 
                                : FileImage(File(entry.value.path)) as ImageProvider,
                            fit: BoxFit.cover,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _showFullScreenImage(entry.value.path),
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),

                      Positioned(
                        top: -8,
                        right: 4,
                        child: InkWell(
                          onTap: () => setState(() => _selectedImages.removeAt(entry.key)),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
                            child: const Icon(Icons.close_rounded, size: 14, color: AppTheme.textMain),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ],
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitInquiry,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryIndigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 0,
              ),
              child: _isSubmitting 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('문의 접수하기', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label, String value) {
    bool isSelected = _category == value;
    return InkWell(
      onTap: () => setState(() => _category = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryIndigo : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? AppTheme.primaryIndigo : AppTheme.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textSub,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildInquiryHistory() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return const Center(child: Text('로그인이 필요합니다.'));

    return Column(
      children: [
        // Category Filter
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('전체', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('질문', 'question'),
                const SizedBox(width: 8),
                _buildFilterChip('버그', 'bug'),
                const SizedBox(width: 8),
                _buildFilterChip('건의', 'suggestion'),
              ],
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _inquiriesStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              var inquiries = snapshot.data ?? [];
              
              // Local filtering for category since stream builder might only support single eq
              if (_historyFilter != 'all') {
                inquiries = inquiries.where((inq) => inq['category'] == _historyFilter).toList();
              }

              if (inquiries.isEmpty) {
                return Center(child: Text(_historyFilter == 'all' ? '문의 내역이 없습니다.' : '해당 카테고리의 문의가 없습니다.', style: const TextStyle(color: AppTheme.textSub, fontWeight: FontWeight.bold)));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: inquiries.length,
                itemBuilder: (context, index) {
                  final inquiry = inquiries[index];
                  final status = inquiry['status'];
                  final category = inquiry['category'];
                  
                  // Notification Logic (Unread check)
                  final hasUnread = inquiry['is_user_unread'] == true;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppTheme.divider.withOpacity(0.3)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: InkWell(
                        onTap: () => _showInquiryDetail(context, inquiry),
                        borderRadius: BorderRadius.circular(24),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(8)),
                                        child: Text(
                                          inquiry['category'] == 'bug' ? '버그' : (inquiry['category'] == 'suggestion' ? '건의' : '질문'),
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppTheme.textSub),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        DateFormat('yyyy.MM.dd').format(DateTime.parse(inquiry['created_at'])),
                                        style: const TextStyle(fontSize: 11, color: AppTheme.textSub, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      if (hasUnread)
                                        Container(
                                          margin: const EdgeInsets.only(right: 8),
                                          width: 6,
                                          height: 6,
                                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                        ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: inquiry['status'] == 'completed' ? AppTheme.divider.withOpacity(0.2) : (inquiry['status'] == 'in_progress' ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1)),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          inquiry['status'] == 'completed' ? '상담 완료' : (inquiry['status'] == 'in_progress' ? '상담 진행' : '답변 대기'),
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: inquiry['status'] == 'completed' ? AppTheme.textSub : (inquiry['status'] == 'in_progress' ? Colors.green : Colors.orange)),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                title: const Text('문의 삭제', style: TextStyle(fontWeight: FontWeight.bold)),
                                                content: const Text('해당 문의 내역을 삭제하시겠습니까?\n삭제된 내역은 복구할 수 없습니다.'),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소', style: TextStyle(color: AppTheme.textSub))),
                                                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              _deleteInquiry(inquiry['id']);
                                            }
                                          },
                                          borderRadius: BorderRadius.circular(20),
                                          child: const Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.textSub),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(inquiry['title'], style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.textMain)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Stream<List<Map<String, dynamic>>> _getFilteredInquiriesStream(String userId) {
    return Supabase.instance.client
        .from('inquiries')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false);
  }

  Widget _buildFilterChip(String label, String value) {
    bool isSelected = _historyFilter == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: isSelected ? Colors.white : AppTheme.textSub)),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _historyFilter = value);
      },
      selectedColor: AppTheme.primaryIndigo,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isSelected ? AppTheme.primaryIndigo : AppTheme.divider)),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }

  Future<void> _deleteInquiry(String inquiryId) async {
    try {
      await Supabase.instance.client
          .from('inquiries')
          .delete()
          .eq('id', inquiryId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('문의가 삭제되었습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  void _showInquiryDetail(BuildContext context, Map<String, dynamic> inquiry) async {
    // Mark as read (is_user_unread = false)
    // The query is still needed to clear the red dot for the user when they just view.
    // However, we should be careful with RLS. The trigger handles replies, 
    // but simple viewing still needs a manual update.
    try {
      await Supabase.instance.client
          .from('inquiries')
          .update({
            'user_last_read_at': DateTime.now().toUtc().toIso8601String(),
            'is_user_unread': false,
          })
          .eq('id', inquiry['id']);
    } catch (e) {
      debugPrint('Error marking as read: $e');
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => _InquiryDetailScreen(inquiry: inquiry),
        ),
      );
    }
  }

  Widget _buildLabel(String text) {
    return Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppTheme.textSub));
  }

  InputDecoration _buildInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppTheme.textSub, fontWeight: FontWeight.w500),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppTheme.divider)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppTheme.divider)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppTheme.primaryIndigo, width: 2)),
    );
  }
  void _showFullScreenImage(String imagePath, {bool isNetwork = false}) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black,
      pageBuilder: (context, _, __) {
        return Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: isNetwork 
                    ? Image.network(imagePath) 
                    : kIsWeb 
                        ? Image.network(imagePath) 
                        : Image.file(File(imagePath)),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, color: Colors.white, size: 30),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InquiryDetailScreen extends StatefulWidget {
  final Map<String, dynamic> inquiry;
  const _InquiryDetailScreen({required this.inquiry});

  @override
  State<_InquiryDetailScreen> createState() => _InquiryDetailScreenState();
}

class _InquiryDetailScreenState extends State<_InquiryDetailScreen> {
  bool _isHeaderExpanded = false;
  final _replyController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;
  late Stream<List<Map<String, dynamic>>> _responsesStream;
  late StreamSubscription<List<Map<String, dynamic>>> _inquirySubscription;
  late StreamSubscription<List<Map<String, dynamic>>> _responsesSubscription;
  late Map<String, dynamic> _currentInquiry;
  final List<XFile> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    if (_selectedImages.length >= 5) {
      if (mounted) SnackBarUtil.showSnackBar(context, message: '이미지는 최대 5장까지 첨부할 수 있습니다.', isError: true);
      return;
    }

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
      );
      if (image == null) return;
      setState(() => _selectedImages.add(image));
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  // Removed _compressImage for Web compatibility

  Future<List<String>> _uploadImages(String userId) async {
    List<String> urls = [];
    for (var image in _selectedImages) {
      final ext = image.name.split('.').last;
      final fileName = '${userId}/${DateTime.now().millisecondsSinceEpoch}_${image.hashCode}.$ext';
      final storageRef = Supabase.instance.client.storage.from('inquiry_images');
      
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        await storageRef.uploadBinary(fileName, bytes);
      } else {
        await storageRef.upload(fileName, File(image.path));
      }

      final imageUrl = storageRef.getPublicUrl(fileName);
      urls.add(imageUrl);
    }
    return urls;
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showFullScreenImage(String imagePath, {bool isNetwork = false}) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black,
      pageBuilder: (context, _, __) {
        return Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: isNetwork 
                    ? Image.network(imagePath) 
                    : kIsWeb 
                        ? Image.network(imagePath) 
                        : Image.file(File(imagePath)),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, color: Colors.white, size: 30),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _currentInquiry = widget.inquiry;
    _responsesStream = Supabase.instance.client
        .from('inquiry_responses')
        .stream(primaryKey: ['id'])
        .eq('inquiry_id', widget.inquiry['id'])
        .order('created_at', ascending: true);
    
    // Listen to status changes of the inquiry
    _inquirySubscription = Supabase.instance.client
        .from('inquiries')
        .stream(primaryKey: ['id'])
        .eq('id', widget.inquiry['id'])
        .listen((data) {
          if (data.isNotEmpty && mounted) {
            setState(() => _currentInquiry = data.first);
          }
        });

    // Listen to responses for auto-scrolling
    _responsesSubscription = _responsesStream.listen((data) {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
      }
    });
  }

  @override
  void dispose() {
    _replyController.dispose();
    _scrollController.dispose();
    _inquirySubscription.cancel();
    _responsesSubscription.cancel();
    super.dispose();
  }

  Future<void> _sendReply() async {
    if (_replyController.text.trim().isEmpty && _selectedImages.isEmpty) return;
    
    setState(() => _isSending = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final imageUrls = await _uploadImages(user.id);

      await Supabase.instance.client.from('inquiry_responses').insert({
        'inquiry_id': _currentInquiry['id'],
        'content': _replyController.text.trim(),
        'images': imageUrls,
      });
      
      // No manual update needed here as handle_inquiry_response_flags trigger
      // automatically updates inquiries table on responses insert.
      // This prevents permission errors and ensures data consistency.

      _replyController.clear();
      setState(() => _selectedImages.clear());
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showSnackBar(
          context,
          message: '전송에 실패했습니다.',
          isError: true,
          technicalDetails: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = _currentInquiry['status'] == 'completed';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('문의 상담', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain, fontSize: 17)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textMain, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Collapsible Header: Original Inquiry Information
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => setState(() => _isHeaderExpanded = !_isHeaderExpanded),
                  child: Row(
                    children: [
                      const Icon(Icons.help_outline_rounded, size: 16, color: AppTheme.primaryIndigo),
                      const SizedBox(width: 6),
                      const Text('문의 원본 내용', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppTheme.primaryIndigo)),
                      const Spacer(),
                      Icon(
                        _isHeaderExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: AppTheme.textSub,
                      ),
                    ],
                  ),
                ),
                if (_isHeaderExpanded) ...[
                  const SizedBox(height: 16),
                  Text(_currentInquiry['title'], style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppTheme.textMain)),
                  const SizedBox(height: 8),
                  Text(_currentInquiry['content'], style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: AppTheme.textMain, height: 1.6)),
                  if (_currentInquiry['images'] != null && (_currentInquiry['images'] as List).isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 80,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: (_currentInquiry['images'] as List).length,
                        separatorBuilder: (context, index) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          return GestureDetector(
                            onTap: () => _showFullScreenImage((_currentInquiry['images'] as List)[index], isNetwork: true),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                (_currentInquiry['images'] as List)[index],
                                width: 80, height: 80, fit: BoxFit.cover,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      DateFormat('yyyy.MM.dd HH:mm').format(DateTime.parse(_currentInquiry['created_at'])),
                      style: const TextStyle(fontSize: 11, color: AppTheme.textSub),
                    ),
                  ),
                ],
                if (!_isHeaderExpanded)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _currentInquiry['title'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.textMain),
                    ),
                  ),
              ],
            ),
          ),
          
          Expanded(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(child: Divider(color: AppTheme.divider)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('상담 이력', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.textSub)),
                      ),
                      Expanded(child: Divider(color: AppTheme.divider)),
                    ],
                  ),
                ),
                
                // Chat History
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _responsesStream,
                    builder: (context, snapshot) {
                      final responses = snapshot.data ?? [];
                      if (responses.isEmpty) {
                        return const Center(child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Text('아직 관리자의 답변이 없습니다.', style: TextStyle(color: AppTheme.textSub, fontWeight: FontWeight.w600)),
                        ));
                      }
                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
                        itemCount: responses.length,
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        itemBuilder: (context, index) {
                          final res = responses[index];
                          final isAdmin = res['admin_id'] != null;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Align(
                              alignment: isAdmin ? Alignment.centerLeft : Alignment.centerRight,
                              child: Column(
                                crossAxisAlignment: isAdmin ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                                children: [
                                  if (res['content'] != null && res['content'].toString().trim().isNotEmpty)
                                    Container(
                                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: isAdmin ? Colors.white : AppTheme.primaryIndigo,
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(20),
                                          topRight: const Radius.circular(20),
                                          bottomLeft: isAdmin ? Radius.zero : const Radius.circular(20),
                                          bottomRight: isAdmin ? const Radius.circular(20) : Radius.zero,
                                        ),
                                        boxShadow: isAdmin ? [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5, offset: const Offset(0, 2))] : null,
                                        border: isAdmin ? Border.all(color: AppTheme.divider.withOpacity(0.5)) : null,
                                      ),
                                      child: Text(res['content'], style: TextStyle(fontWeight: FontWeight.w600, height: 1.5, color: isAdmin ? AppTheme.textMain : Colors.white, fontSize: 14)),
                                    ),
                                  if (res['images'] != null && (res['images'] as List).isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 4, runSpacing: 4,
                                      alignment: isAdmin ? WrapAlignment.start : WrapAlignment.end,
                                      children: (res['images'] as List).map<Widget>((img) {
                                        return GestureDetector(
                                          onTap: () => _showFullScreenImage(img, isNetwork: true),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.network(img, width: 120, height: 120, fit: BoxFit.cover),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(DateFormat('HH:mm').format(DateTime.parse(res['created_at'])), style: const TextStyle(fontSize: 10, color: AppTheme.textSub, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          
          // Chat Input
          Container(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
            ),
            child: isCompleted
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(16)),
                  child: const Text('해당 문의는 답변이 완료되어 종료되었습니다.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSub, fontWeight: FontWeight.bold)),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_selectedImages.isNotEmpty)
                      Container(
                        height: 80,
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _selectedImages.length,
                          separatorBuilder: (context, index) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: kIsWeb
                                      ? Image.network(_selectedImages[index].path, width: 80, height: 80, fit: BoxFit.cover)
                                      : Image.file(File(_selectedImages[index].path), width: 80, height: 80, fit: BoxFit.cover),
                                ),
                                Positioned(
                                  top: -4, right: -4,
                                  child: InkWell(
                                    onTap: () => setState(() => _selectedImages.removeAt(index)),
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
                                      child: const Icon(Icons.close, size: 14, color: AppTheme.textMain),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.add_photo_alternate_outlined, color: AppTheme.primaryIndigo),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _replyController,
                            decoration: InputDecoration(
                              hintText: '추가적인 궁금증이 있나요?',
                              hintStyle: const TextStyle(fontSize: 14, color: AppTheme.textSub, fontWeight: FontWeight.w600),
                              filled: true,
                              fillColor: AppTheme.background,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            ),
                            maxLines: null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: _isSending ? null : _sendReply,
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(color: AppTheme.primaryIndigo, shape: BoxShape.circle),
                            child: _isSending 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
          ),
        ],
      ),
    );
  }
}
