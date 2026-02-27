import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rive/rive.dart';
import 'package:elevenlabs_agents/elevenlabs_agents.dart';
import 'package:permission_handler/permission_handler.dart';

import '../ui/app_background.dart';
import '../ui/app_palette.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  // ── ElevenLabs ──
  static const _agentId = 'agent_5201kjewn19jf7k8fa3astsrksm9';
  late ConversationClient _client;

  // ── Rive ──
  // The .riv file has a ViewModel Enum property "enumProperty" (values: Idle, Talking)
  // bound to "State Machine 1" transitions via Data Binding.
  // We use AutoBind() so the runtime auto-creates the ViewModel instance,
  // then call: _vmi?.enumerator('enumProperty')?.value = 'Talking'
  ViewModelInstance? _vmi;

  // FileLoader must be created ONCE (in initState) and reused across rebuilds.
  // If it's created inline in build(), every setState() produces a new instance
  // that is != the old one, causing RiveWidgetBuilder to reload the .riv file
  // from scratch on every rebuild → white flash / "cheshire cat" effect.
  late final FileLoader _riveFileLoader;

  // ── Avatar zoom / framing ─────────────────────────────────
  // Increase _avatarScale to zoom in further (1.0 = fit artboard)
  // _avatarAlignment: negative y pans upward to show the face
  // NOTE: `RiveWidget(fit: Fit.cover)` + high scale can over-crop on wide web
  // viewports. Keep these conservative.
  static const double _avatarScale = 1.64;
  static const Alignment _avatarAlignment = Alignment(0.0, -1.15);

  // ── UI state ──
  final List<_ChatMessage> _messages = [];
  bool _isSpeaking = false;
  String _status = 'disconnected';

  // ── Typewriter ──
  // Drip interval: ~50 ms ≈ 20 chars/sec, close to natural speech pace.
  static const _typewriterInterval = Duration(milliseconds: 50);
  Timer? _typewriterTimer;

  void _startTypewriter() {
    // If the timer is already running, don't restart it — streaming events from
    // ElevenLabs can arrive faster than the 50ms tick interval, and cancelling
    // then recreating the timer on every event means it never actually fires.
    // The active timer will naturally pick up the latest `text` value since
    // _messages[idx].text is updated in-place by the streaming callbacks.
    if (_typewriterTimer?.isActive ?? false) return;

    _typewriterTimer = Timer.periodic(_typewriterInterval, (_) {
      final idx = _findActiveAgentMessageIndex();
      if (idx == null) {
        _typewriterTimer?.cancel();
        return;
      }
      final msg = _messages[idx];
      if (msg.displayText.length < msg.text.length) {
        // Add one character at a time; setState triggers a rebuild.
        msg.displayText = msg.text.substring(0, msg.displayText.length + 1);
        if (mounted) setState(() {});
      } else if (msg.finalized) {
        _typewriterTimer?.cancel();
      }
    });
  }

  void _snapTypewriter() {
    _typewriterTimer?.cancel();
    final idx = _findActiveAgentMessageIndex();
    if (idx != null) {
      _messages[idx].displayText = _messages[idx].text;
    }
    // Also snap any older non-finalized messages (safety).
    for (final m in _messages) {
      if (m.isAgent) m.displayText = m.text;
    }
    if (mounted) setState(() {});
  }

  // ── Debug panel ──
  bool _showDebug = false;
  String _manualState = 'Idle';

  @override
  void initState() {
    super.initState();
    // Create the FileLoader once — reused across every rebuild.
    _riveFileLoader = FileLoader.fromAsset(
      'assets/andrew_avatar.riv',
      riveFactory: Factory.rive,
    );
    _initElevenLabs();
  }

  // ─────────────────────────────────────────────
  // ElevenLabs setup
  // ─────────────────────────────────────────────

  int? _findActiveAgentMessageIndex() {
    for (int i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.isAgent && !m.finalized) return i;
    }
    return null;
  }

  void _initElevenLabs() {
    _client = ConversationClient(
      callbacks: ConversationCallbacks(
        onConnect: ({required conversationId}) {
          debugPrint('[EL] Connected: $conversationId');
          setState(() => _status = 'connected');
        },
        onDisconnect: (_) {
          debugPrint('[EL] Disconnected');
          setState(() {
            _status = 'disconnected';
            _setSpeaking(false);
          });
        },
        // Streaming agent response — onTentativeAgentResponse fires repeatedly
        // with progressively longer strings (the full text so far each time).
        // We update the target text and let the typewriter timer drip characters
        // into displayText one at a time.
        onTentativeAgentResponse: ({required response}) {
          setState(() {
            final idx = _findActiveAgentMessageIndex();
            if (idx != null) {
              _messages[idx].text = response;
            } else {
              _messages.add(_ChatMessage(text: response, isAgent: true, finalized: false));
            }
          });
          _startTypewriter();
        },
        // Final agent message — snap remaining characters instantly then finalize.
        onMessage: ({required message, required source}) {
          if (source == Role.ai) {
            debugPrint('[EL] agent final: $message');
            setState(() {
              final idx = _findActiveAgentMessageIndex();
              if (idx != null) {
                _messages[idx].text = message;
                _messages[idx].finalized = true;
              } else {
                // Fallback: if we somehow missed streaming, still show the final.
                _messages.add(_ChatMessage(text: message, isAgent: true, finalized: true));
              }
            });
            _snapTypewriter();
          }
        },
        // User final transcript
        onUserTranscript: ({required transcript, required eventId}) {
          debugPrint('[EL] user transcript: $transcript');
          setState(() {
            _messages.add(_ChatMessage(text: transcript, isAgent: false, finalized: true));
          });
        },
        onModeChange: ({required mode}) {
          debugPrint('[EL] Mode → ${mode.name}');
          _setSpeaking(mode == ConversationMode.speaking);
        },
        onError: (message, [context]) {
          debugPrint('[EL] Error: $message');
          _showSnackBar('Error: $message');
        },
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Bridge: ElevenLabs mode → ViewModel Enum
  // Values are the string names from the Rive enum: 'Idle' / 'Talking'
  // ─────────────────────────────────────────────
  void _setSpeaking(bool speaking) {
    if (_isSpeaking == speaking) return;
    _isSpeaking = speaking;
    _setEnumValue(speaking ? 'Talking' : 'Idle');
    if (mounted) setState(() {});
  }

  void _setEnumValue(String value) {
    _vmi?.enumerator('enumProperty')?.value = value;
    _manualState = value;
    debugPrint('[Bridge] enumProperty → "$value"');
    if (mounted) setState(() {});
  }

  // ─────────────────────────────────────────────
  // Conversation controls
  // ─────────────────────────────────────────────
  Future<void> _startConversation() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      _showSnackBar('Microphone permission is required');
      return;
    }

    setState(() => _status = 'connecting');

    try {
      await _client.startSession(agentId: _agentId);
    } catch (e) {
      debugPrint('[EL] Failed to start: $e');
      _showSnackBar('Failed to connect: $e');
      setState(() => _status = 'disconnected');
    }
  }

  Future<void> _endConversation() async {
    await _client.endSession();
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  @override
  void dispose() {
    _typewriterTimer?.cancel();
    _client.dispose();
    _vmi?.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isConnected = _status == 'connected';
    final isDisconnected = _status == 'disconnected';

    return Scaffold(
      body: AppBackground(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Avatar fills the entire screen behind the UI ──
            Positioned.fill(child: _buildAvatar()),

            // ── Top HUD pills — pinned to top of screen ──
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Row(
                    children: [
                      _Pill(
                        icon: Icons.auto_awesome,
                        label: 'vTuber English Lesson',
                        color: AppPalette.primaryAccent,
                      ),
                      const SizedBox(width: 8),
                      _IconPillButton(
                        tooltip: 'Toggle debug panel',
                        icon: _showDebug ? Icons.bug_report : Icons.bug_report_outlined,
                        onPressed: () => setState(() => _showDebug = !_showDebug),
                      ),
                      const Spacer(),
                      _Pill(
                        icon: _status == 'connected'
                            ? (_isSpeaking ? Icons.record_voice_over : Icons.hearing)
                            : (_status == 'connecting' ? Icons.sync : Icons.power_settings_new),
                        label: _status == 'connected'
                            ? (_isSpeaking ? 'Speaking' : 'Listening')
                            : (_status == 'connecting' ? 'Connecting' : 'Offline'),
                        color: _status == 'connected'
                            ? (_isSpeaking ? AppPalette.secondaryShade : AppPalette.primaryShade)
                            : AppPalette.tertiaryShade,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Bottom UI panel (status + debug + chat + controls) ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Status bar ──
                    _buildStatusBar(),

                    // ── Debug panel ──
                    if (_showDebug) _buildDebugPanel(),

                    // ── Chat messages (fixed height) ──
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.28,
                      child: _buildChatList(),
                    ),

                    // ── Controls ──
                    _buildControls(isConnected, isDisconnected),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Rive avatar widget — new 0.14.3 API
  // RiveWidgetBuilder loads the file, creates a RiveWidgetController,
  // auto-binds the single consolidated ViewModel (DataBind.auto()), and calls
  // onLoaded with a RiveLoaded state containing the ViewModelInstance.
  //
  // The .riv now has ONE ViewModel "CharacterData" containing both:
  //   • Lua script properties (bodyRot, headRot, iris1X/Y, iris2X/Y, …)
  //   • enumProperty (Idle / Talking) — for SM state transitions
  // DataBind.auto() binds it to both the artboard AND the state machine,
  // so scripts work AND enum transitions work — no manual VM iteration needed.
  // ─────────────────────────────────────────────
  Widget _buildAvatar() {
    return ClipRect(
      child: RiveWidgetBuilder(
        fileLoader: _riveFileLoader,
        stateMachineSelector: const StateMachineNamed('State Machine 1'),
        dataBind: DataBind.auto(),
        onLoaded: (state) {
          final vmi = state.viewModelInstance;
          debugPrint('[Rive] onLoaded — VMI props: ${vmi?.properties.map((p) => p.name).toList()}');
          final enumProp = vmi?.enumerator('enumProperty');
          debugPrint('[Rive] enumProperty: ${enumProp != null ? "✓ value=${enumProp.value}" : "✗ not found"}');
          enumProp?.value = 'Idle';
          setState(() { _vmi = vmi; });
        },
        onFailed: (error, stackTrace) {
          debugPrint('[Rive] ❌ RiveWidgetBuilder failed: $error\n$stackTrace');
        },
        builder: (context, state) {
          return switch (state) {
            RiveLoaded(:final controller) => Transform.scale(
                scale: _avatarScale,
                alignment: _avatarAlignment,
                child: ColoredBox(
                  // Ensures we never see "white" behind the avatar if the Rive artboard
                  // has transparent regions (or if Flutter background is bright).
                  color: Colors.transparent,
                  child: RiveWidget(
                    controller: controller,
                    // `Fit.contain` avoids aggressive cropping that can push the
                    // character out of frame on wide web layouts.
                    fit: Fit.contain,
                  ),
                ),
              ),
            RiveLoading() => const Center(
                child: CircularProgressIndicator(),
              ),
            RiveFailed(:final error) => Center(
                child: Text(
                  'Failed to load avatar:\n$error',
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ),
          };
        },
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Debug panel
  // ─────────────────────────────────────────────
  Widget _buildDebugPanel() {
    final hasVmi = _vmi != null;
    final enumProp = hasVmi ? _vmi!.enumerator('enumProperty') : null;
    final currentVal = enumProp?.value ?? '(not bound)';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0A2E).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.7), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🐛 Rive Debug',
              style: TextStyle(
                  color: Colors.purple[200],
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
          const SizedBox(height: 6),

          // ViewModel instance status
          Text(
            'ViewModelInstance: ${hasVmi ? "✓ bound" : "✗ not yet bound (waiting for onLoaded)"}',
            style: TextStyle(
              color: hasVmi ? Colors.greenAccent : Colors.redAccent,
              fontSize: 11,
            ),
          ),
          Text(
            'enumProperty: ${enumProp != null ? "✓ found — value: $currentVal" : "✗ not found"}',
            style: TextStyle(
              color: enumProp != null ? Colors.greenAccent : Colors.redAccent,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),

          // Manual Idle / Talking buttons
          const Text('Manual state:',
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _setEnumValue('Idle'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _manualState == 'Idle'
                        ? Colors.greenAccent
                        : Colors.white54,
                    side: BorderSide(
                        color: _manualState == 'Idle'
                            ? Colors.greenAccent
                            : Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('▶ Idle'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _setEnumValue('Talking'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _manualState == 'Talking'
                        ? Colors.orangeAccent
                        : Colors.white54,
                    side: BorderSide(
                        color: _manualState == 'Talking'
                            ? Colors.orangeAccent
                            : Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('▶ Talking'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    String statusText;
    switch (_status) {
      case 'connected':
        statusText = _isSpeaking ? '🗣 Speaking' : '🎧 Listening';
        break;
      case 'connecting':
        statusText = '⏳ Connecting...';
        break;
      default:
        statusText = '⏸ Disconnected';
    }

    final statusColor = switch (_status) {
      'connected' => _isSpeaking ? AppPalette.secondaryShade : AppPalette.primaryShade,
      'connecting' => AppPalette.tertiary,
      _ => AppPalette.tertiaryShade,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        border: Border(
          top: BorderSide(color: AppPalette.navyBlack.withValues(alpha: 0.12)),
          bottom: BorderSide(color: AppPalette.navyBlack.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppPalette.navyBlack.withValues(alpha: 0.35),
                width: 2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              statusText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppPalette.navyBlack,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 20),
        ],
      ),
    );
  }

  Widget _buildChatList() {
    if (_messages.isEmpty) {
      return _buildChalkboardPanel(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 2,
              ),
            ),
            child: const Text(
              'Your English Teacher is ready!\nPress Start Lesson to begin.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
                height: 1.25,
              ),
            ),
          ),
        ),
      );
    }

    return _buildChalkboardPanel(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        reverse: true,
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final msg = _messages[_messages.length - 1 - index];
          return _buildMessageBubble(msg);
        },
      ),
    );
  }

  Widget _buildChalkboardPanel({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppPalette.navyBlack, width: 3),
            boxShadow: [
              BoxShadow(
                color: AppPalette.navyBlack.withValues(alpha: 0.18),
                offset: const Offset(0, 10),
                blurRadius: 20,
              ),
            ],
          ),
          child: Stack(
            children: [
              // Semi-transparent chalkboard surface.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    // More opaque so the classroom/pattern never dominates readability.
                    color: const Color(0xff0B1C23).withValues(alpha: 0.86),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xff0B1C23).withValues(alpha: 0.90),
                        const Color(0xff142C33).withValues(alpha: 0.84),
                      ],
                    ),
                  ),
                ),
              ),

              // Light texture — slightly scaled so seams are less prominent.
              Positioned.fill(
                child: Image.asset(
                  'assets/ui/pattern_background.png',
                  repeat: ImageRepeat.repeat,
                  color: Colors.white.withValues(alpha: 0.07),
                  colorBlendMode: BlendMode.srcATop,
                  scale: 0.5,
                ),
              ),

              // Content
              Positioned.fill(child: child),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg) {
    return Align(
      alignment: msg.isAgent ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: msg.isAgent
              ? const Color(0xFF102128).withValues(alpha: 0.92)
              : AppPalette.primaryShade.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.14),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: AppPalette.navyBlack.withValues(alpha: 0.12),
              offset: const Offset(0, 6),
              blurRadius: 14,
            )
          ],
        ),
        child: Text(
          msg.displayText,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.92),
            fontSize: 14,
            height: 1.25,
          ),
        ),
      ),
    );
  }

  Widget _buildControls(bool isConnected, bool isDisconnected) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        border: Border(top: BorderSide(color: AppPalette.navyBlack.withValues(alpha: 0.12))),
      ),
      child: Row(
        children: [
          if (isConnected) ...[
            IconButton(
              onPressed: () => _client.toggleMute(),
              icon: Icon(
                _client.isMuted ? Icons.mic_off : Icons.mic,
                color: _client.isMuted ? AppPalette.secondaryShade : AppPalette.navyBlack,
              ),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.85),
                side: BorderSide(color: AppPalette.navyBlack.withValues(alpha: 0.35), width: 2),
                padding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(width: 12),
          ],

          Expanded(
            child: ElevatedButton(
              onPressed: isDisconnected
                  ? _startConversation
                  : isConnected
                      ? _endConversation
                      : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isConnected ? AppPalette.secondaryShade : AppPalette.primaryAccent,
                foregroundColor: Colors.white,
                side: const BorderSide(color: AppPalette.navyBlack, width: 3),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                isConnected
                    ? 'End Lesson'
                    : _status == 'connecting'
                        ? 'Connecting...'
                        : 'Start Lesson',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppPalette.navyBlack.withValues(alpha: 0.55), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppPalette.navyBlack,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconPillButton extends StatelessWidget {
  const _IconPillButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppPalette.navyBlack.withValues(alpha: 0.55),
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Icon(
              icon,
              size: 16,
              color: AppPalette.navyBlack,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Chat message model
// text is mutable for streaming updates
// finalized: false while onTentativeAgentResponse is still updating it
// ─────────────────────────────────────────────
class _ChatMessage {
  /// Full target text (updated by streaming callbacks).
  String text;
  /// Characters revealed so far — the typewriter drips from displayText.length → text.length.
  String displayText;
  final bool isAgent;
  bool finalized;
  _ChatMessage({required this.text, required this.isAgent, this.finalized = true})
      : displayText = isAgent ? '' : text; // User messages show instantly.
}
