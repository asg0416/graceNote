import 'package:flutter/material.dart';
import 'package:grace_note/core/theme/app_theme.dart';
import 'package:lucide_icons/lucide_icons.dart' as lucide;

class ServiceGuideScreen extends StatefulWidget {
  const ServiceGuideScreen({super.key});

  @override
  State<ServiceGuideScreen> createState() => _ServiceGuideScreenState();
}

class _ServiceGuideScreenState extends State<ServiceGuideScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('서비스 지원', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textMain, fontSize: 17, fontFamily: 'Pretendard', letterSpacing: -0.5)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: AppTheme.border, width: 1)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppTheme.textMain, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryViolet,
          unselectedLabelColor: AppTheme.textSub,
          indicatorColor: AppTheme.primaryViolet,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, fontFamily: 'Pretendard'),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, fontFamily: 'Pretendard'),
          tabs: const [
            Tab(text: '사용 가이드'),
            Tab(text: '자주 묻는 질문'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUsageGuideTab(),
          _buildFAQTab(),
        ],
      ),
    );
  }


  Widget _buildUsageGuideTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      physics: const BouncingScrollPhysics(),
      children: [
        _buildGuideSection(
          '시스템 운영 정책',
          '그레이스노트는 교회의 승인을 받은 분들만 이용할 수 있는 폐쇄형 서비스입니다.\n\n'
          '• 관리자가 사전에 등록한 성도 정보(이름, 전화번호)가 일치해야 가입 및 이용이 가능합니다.\n'
          '• 소속된 조(그룹)가 있어야 앱의 주요 기능을 사용할 수 있습니다.',
          lucide.LucideIcons.shieldCheck,
        ),
        _buildGuideSection(
          '메인 화면 (나의 기도)',
          '나의 기도 제목을 작성하고 AI의 도움을 받아 정제할 수 있습니다.\n\n'
          '• AI 정제: 작성한 기도 제목을 더 깊이 있고 은혜로운 문장으로 다듬어줍니다.\n'
          '• 공유 설정: 작성한 기도는 소속된 조원들에게만 공유됩니다.',
          lucide.LucideIcons.penTool,
        ),
        _buildGuideSection(
          '기도소식',
          '우리 조원들과 교회 전체의 기도 제목을 확인하고 함께 기도할 수 있습니다.\n\n'
          '• 아멘: 함께 기도하고 있다는 마음을 표현할 수 있습니다.\n'
          '• 저장하기: 나중에 다시 보고 싶은 기도 제목을 즐겨찾기에 추가할 수 있습니다.',
          lucide.LucideIcons.heart,
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildGuideSection(String title, String content, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.border, width: 1.0),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryViolet.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppTheme.primaryViolet, size: 20),
              ),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textMain, fontFamily: 'Pretendard')),
            ],
          ),
          const SizedBox(height: 16),
          Text(content, style: const TextStyle(fontSize: 14, color: AppTheme.textSub, height: 1.6, fontFamily: 'Pretendard')),
        ],
      ),
    );
  }

  Widget _buildFAQTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      physics: const BouncingScrollPhysics(),
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 20),
          child: Text('궁금하신 점을 빠르게 확인해보세요.', style: TextStyle(fontSize: 14, color: AppTheme.textSub, fontWeight: FontWeight.w600, fontFamily: 'Pretendard')),
        ),
        _buildAccordionItem(
          '회원가입이 안 돼요.',
          '관리자가 성도님을 사전에 등록하지 않았거나, 입력하신 전화번호가 등록된 정보와 다를 수 있습니다. 교회 사무실이나 조장님께 문의하여 등록 정보를 확인해 주세요.',
        ),
        _buildAccordionItem(
          '조편성 정보가 달라요.',
          '관리자(또는 조장)가 조편성을 변경한 후 "변경사항 확정"을 눌러야 앱에 실제로 반영됩니다. 최신 정보가 보이지 않는다면 조장님께 확정 여부를 확인해 보세요.',
        ),
        _buildAccordionItem(
          '기도제목을 수정하고 싶어요.',
          '메인 화면의 "나의 기도" 탭에서 작성하신 기도제목의 우측 상단 메뉴 버튼(점 세 개)을 눌러 수정하실 수 있습니다.',
        ),
        _buildAccordionItem(
          'AI 정제는 무제한인가요?',
          '현재 베타 기간 동안은 자유롭게 이용하실 수 있습니다. 다만, 시스템 과부하 방지를 위해 일일 사용 횟수가 제한될 수 있습니다.',
        ),
      ],
    );
  }

  Widget _buildAccordionItem(String question, String answer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border, width: 1.0),
      ),
      child: ExpansionTile(
        title: Text(
          question, 
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textMain, fontFamily: 'Pretendard')
        ),
        iconColor: AppTheme.primaryViolet,
        collapsedIconColor: AppTheme.textSub,
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        expandedAlignment: Alignment.topLeft,
        children: [
          Divider(height: 1, color: AppTheme.border.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            answer,
            style: const TextStyle(fontSize: 14, color: AppTheme.textSub, height: 1.6, fontFamily: 'Pretendard'),
          ),
        ],
      ),
    );
  }
}
