import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import 'payment_models.dart';

enum CheckoutOutcome { approved, cancelled }

/// Hosts PayPal's own approval page. The buyer signs in and approves inside
/// PayPal; FLOWMINT never sees their credentials. Reaching the return URL only
/// means "the buyer approved" — the payment is confirmed later by the
/// backend capture, not by this screen.
class PayPalCheckoutScreen extends StatefulWidget {
  const PayPalCheckoutScreen({super.key, required this.session});

  final CheckoutSession session;

  @override
  State<PayPalCheckoutScreen> createState() => _PayPalCheckoutScreenState();
}

class _PayPalCheckoutScreenState extends State<PayPalCheckoutScreen> {
  late final WebViewController _controller;
  double _progress = 0;
  String? _loadError;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => _intercept(request.url)
              ? NavigationDecision.prevent
              : NavigationDecision.navigate,
          onPageStarted: _intercept,
          onUrlChange: (change) {
            if (change.url != null) _intercept(change.url!);
          },
          onProgress: (p) =>
              mounted ? setState(() => _progress = p / 100) : null,
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? false) {
              setState(
                () => _loadError =
                    'PayPal could not be loaded. Check your connection.',
              );
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.session.approveUrl));
  }

  /// Returns true when the URL is one of our redirect targets.
  bool _intercept(String url) {
    if (_finished) return true;
    final s = widget.session;
    if (url.startsWith(s.returnUrl)) {
      final token = Uri.tryParse(url)?.queryParameters['token'];
      // Ignore a return redirect that is not for this order.
      if (token != null && token != s.paypalOrderId) return true;
      _finish(CheckoutOutcome.approved);
      return true;
    }
    if (url.startsWith(s.cancelUrl)) {
      _finish(CheckoutOutcome.cancelled);
      return true;
    }
    return false;
  }

  void _finish(CheckoutOutcome outcome) {
    if (_finished) return;
    _finished = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(outcome);
    });
  }

  Future<void> _confirmClose() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel checkout?'),
        content: const Text(
          'You have not been charged. You can check out again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continue paying'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel checkout'),
          ),
        ],
      ),
    );
    if (leave == true) _finish(CheckoutOutcome.cancelled);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmClose();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _confirmClose,
          ),
          title: const Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: AppColors.brand,
              ),
              SizedBox(width: Space.xs),
              Text('PayPal secure checkout'),
            ],
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: AnimatedOpacity(
              opacity: _progress < 1 ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: LinearProgressIndicator(value: _progress, minHeight: 2),
            ),
          ),
        ),
        body: _loadError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_loadError!, textAlign: TextAlign.center),
                      const SizedBox(height: Space.md),
                      OutlinedButton(
                        onPressed: () {
                          setState(() => _loadError = null);
                          _controller.reload();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : WebViewWidget(controller: _controller),
      ),
    );
  }
}
