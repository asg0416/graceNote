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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      physics: const BouncingScrollPhysics(),
      children: [
        _buildSectionHeader('시스템 운영 및 권한'),
        _buildUsageAccordionItem(
          '1. 시스템 운영 및 역할 안내',
          '그레이스노트는 교회의 승인을 받은 분들만 이용할 수 있는 폐쇄형 서비스입니다.\n\n'
          '• 가입 및 온보딩: 이메일 또는 소셜 로그인을 통한 가입 후, 이름과 휴대폰 인증으로 소속을 확인하는 온보딩 과정이 필수입니다.\n'
          '• 조장: 조원들의 출석과 나눔 및 기도제목을 기록하고 관리합니다.\n'
          '• 조원: 본인의 기도 타임라인과 부서 전체의 기도 소식을 볼 수 있습니다.\n'
          '• 관리자: 웹페이지에서 가입하며, 전 성도 데이터 조회 및 시스템을 총괄합니다.\n'
          '• 역할 전환: 다중 역할을 가진 경우 [프로필] 하단에서 역할을 전환할 수 있습니다.',
          lucide.LucideIcons.shieldCheck,
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('메뉴별 상세 설명'),
        _buildUsageAccordionItem(
          '[기록] 메뉴 안내',
          '조장이 매주 조원들의 나눔과 기도제목을 기록하는 핵심 공간입니다.\n\n'
          '• 출석체크 자동 팝업: 해당 주차의 출석 기록이 없으면 기록 시작 전 자동으로 체크 화면이 뜹니다.\n'
          '• ✨ AI 정리: 입력한 나눔 내용을 문맥에 맞게 다듬어줍니다. 결과가 마음에 들지 않으면 \'되돌리기\' 버튼으로 수정 전 상태로 복구 가능합니다.\n'
          '• 저장: 작성 중에는 [임시 저장]을 할 수 있으며, [최종 등록하기]를 완료하면 [기도소식]에 공개됩니다.',
          lucide.LucideIcons.penTool,
        ),
        _buildUsageAccordionItem(
          '[기도소식] 메뉴 안내',
          '우리 조와 부서 전체의 기도제목을 확인하는 타임라인입니다.\n\n'
          '• 검색: 성도님 이름이나 키워드로 기도제목을 빠르게 찾을 수 있습니다.\n'
          '• 함께 기도하기: 해당 버튼을 눌러 중보 기도의 마음을 표현할 수 있습니다.\n'
          '• 저장하기: 나중에 다시 보고 싶은 기도제목을 보관하여 모아볼 수 있습니다.',
          lucide.LucideIcons.heart,
        ),
        _buildUsageAccordionItem(
          '[출석] 메뉴 안내',
          '[기록]에서 체크한 출석 현황을 시각적으로 확인하는 메뉴입니다.\n\n'
          '• 출석 통계: 월별 출석 현황을 막대그래프로 한눈에 파악할 수 있습니다.\n'
          '• 명단 확인: 출석 여부를 뱃지 형태로 표시하여 참석자를 직관적으로 보여줍니다.',
          lucide.LucideIcons.barChart2,
        ),
        _buildUsageAccordionItem(
          '[더보기] 메뉴 구성',
          '다양한 관리 및 설정 기능을 제공합니다.\n\n'
          '1. 역할 선택: 프로필 사진 하단에서 현재 역할을 확인하고 전환합니다.\n'
          '2. 저장된 기도제목: \'저장\'하거나 \'함께 기도하기\'를 누른 기도를 모아봅니다.\n'
          '3. 조원 관리: (권한 시) 조원의 추가나 정보 수정을 관리합니다.\n'
          '4. AI 스타일 설정: 말투나 공유 시의 아이콘 등을 취향껏 설정합니다.\n'
          '5. 프로필/계정 관리: 정보를 확인하고 비밀번호를 변경합니다.\n'
          '6. 고객지원: 공지사항, 1:1 문의, 서비스 가이드 등을 이용합니다.',
          lucide.LucideIcons.moreHorizontal,
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('조장 주간 가이드'),
        _buildUsageAccordionItem(
          '매주 해야 할 일 (3단계)',
          '1단계: 모임 출석 체크\n'
          '[기록] 메뉴 진입 시 뜨는 팝업에서 참석 조원을 선택하고 완료합니다.\n\n'
          '2단계: 나눔 기록 및 AI 정리\n'
          '기도제목을 입력하고 [✨ AI 정리]로 정돈합니다. (필요 시 되돌리기 활용)\n\n'
          '3단계: 최종 제출\n'
          '[최종 등록하기]를 누르면 [기도소식]에 즉시 반영됩니다.',
          lucide.LucideIcons.calendarCheck,
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12, top: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: AppTheme.textSub,
          fontFamily: 'Pretendard',
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  Widget _buildUsageAccordionItem(String title, String content, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border, width: 1.0),
      ),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryViolet.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.primaryViolet, size: 18),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.textMain,
            fontFamily: 'Pretendard',
          ),
        ),
        iconColor: AppTheme.primaryViolet,
        collapsedIconColor: AppTheme.textSub,
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        expandedAlignment: Alignment.topLeft,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1, color: AppTheme.border),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textMain,
              height: 1.6,
              fontFamily: 'Pretendard',
            ),
          ),
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
          '관리자가 성도님을 사전에 등록하지 않았거나, 입력하신 정보가 교적부와 다를 수 있습니다. 온보딩 과정에서 실명과 휴대폰 번호가 정확한지 다시 확인해 주시고, 지속될 경우 교회 사무실로 문의해 주세요.',
        ),
        _buildAccordionItem(
          '조편성 정보가 달라요.',
          '조장님이 [기록] 완료 후 [최종 등록하기]를 눌러야 해당 주의 조편성 정보가 앱에 반영됩니다. 최신 정보가 보이지 않는다면 조장님께 등록 여부를 확인해 보세요.',
        ),
        _buildAccordionItem(
          '저장된 기도는 어디서 보나요?',
          '[더보기] 메뉴의 [저장된 기도제목]에서 내가 저장한 기도와 \'함께 기도하기\'를 누른 중보 기도제목들을 모두 확인하실 수 있습니다.',
        ),
        _buildAccordionItem(
          'AI 스타일은 어떻게 바꾸나요?',
          '[더보기] > [AI 스타일 설정] 메뉴에서 AI가 기도제목을 다듬을 때의 말투나 이모지 사용 여부 등을 취향에 맞게 설정할 수 있습니다.',
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
