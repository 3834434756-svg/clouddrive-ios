import UIKit
import WebKit

/// CloudDrive 壳 App：全屏 WKWebView 加载线上云盘页面。
///
/// 设计要点：
/// - 页面自己声明了 `viewport-fit=cover` 并用 `env(safe-area-inset-*)` 处理刘海，
///   所以 WebView 全屏铺满、`contentInsetAdjustmentBehavior = .never`，不额外加内边距。
/// - `target=_blank` 的链接（云盘里常见）不会丢，转成当前 WebView 内加载。
/// - 非 http(s) 协议（tel: / mailto: / 分享出去的 scheme）交给系统打开。
final class ViewController: UIViewController {

    /// 壳 App 加载的线上地址
    private let homeURL = URL(string: "https://ac1be15f60f7d4ccc.sg2.agentos-app.run/")!

    private var webView: WKWebView!
    private let progressBar = UIProgressView(progressViewStyle: .default)
    private let refreshControl = UIRefreshControl()

    private var errorContainer: UIView!
    private var errorLabel: UILabel!
    private var retryButton: UIButton!

    private var progressObservation: NSKeyValueObservation?

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        buildWebView()
        buildProgressBar()
        buildErrorView()

        load(homeURL)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 进度条贴着安全区顶部，避开刘海/状态栏
        progressBar.frame = CGRect(
            x: 0,
            y: view.safeAreaInsets.top,
            width: view.bounds.width,
            height: 3
        )
    }

    deinit {
        progressObservation?.invalidate()
    }

    // MARK: - 构建 UI

    private func buildWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = true
        view.addSubview(webView)
        self.webView = webView

        refreshControl.addTarget(self, action: #selector(onRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            self?.updateProgress(wv.estimatedProgress)
        }
    }

    private func buildProgressBar() {
        progressBar.progressTintColor = UIColor(red: 0.31, green: 0.43, blue: 0.97, alpha: 1.0)
        progressBar.trackTintColor = .clear
        progressBar.alpha = 0
        view.addSubview(progressBar)
    }

    private func buildErrorView() {
        let container = UIView()
        container.backgroundColor = .systemBackground
        container.isHidden = true
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        let label = UILabel()
        label.text = "页面加载失败"
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 15)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        var conf = UIButton.Configuration.filled()
        conf.title = "重试"
        conf.cornerStyle = .medium
        conf.baseBackgroundColor = UIColor(red: 0.31, green: 0.43, blue: 0.97, alpha: 1.0)
        let button = UIButton(configuration: conf)
        button.addTarget(self, action: #selector(onRetry), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -24),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -32),

            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 20),
        ])

        errorContainer = container
        errorLabel = label
        retryButton = button
    }

    // MARK: - 行为

    private func load(_ url: URL) {
        errorContainer.isHidden = true
        webView.load(URLRequest(url: url))
    }

    @objc private func onRefresh() {
        webView.reload()
    }

    @objc private func onRetry() {
        load(homeURL)
    }

    private func updateProgress(_ value: Double) {
        let done = value >= 1.0
        progressBar.setProgress(Float(value), animated: !done)
        progressBar.alpha = done ? 0 : 1
        if done {
            refreshControl.endRefreshing()
        }
    }

    private func showError(_ message: String) {
        errorLabel.text = message
        errorContainer.isHidden = false
        refreshControl.endRefreshing()
        progressBar.alpha = 0
    }
}

// MARK: - WKNavigationDelegate

extension ViewController: WKNavigationDelegate {

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""
        // http/https 留在 App 内；其余协议（tel/mailto/itms-apps/分享 scheme）交给系统
        if scheme == "http" || scheme == "https" || scheme == "about" || scheme == "data" {
            decisionHandler(.allow)
            return
        }

        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        errorContainer.isHidden = true
        refreshControl.endRefreshing()
        progressBar.alpha = 0
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationError(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // 系统回收 WebContent 进程（内存压力）时自动恢复
        webView.reload()
    }

    private func handleNavigationError(_ error: Error) {
        let nsError = error as NSError
        // 主动取消（如点外链跳转）不算失败
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }

        var message = "页面加载失败，请检查网络后重试。"
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                message = "设备未连接网络，请检查 Wi-Fi 或蜂窝数据。"
            case NSURLErrorTimedOut:
                message = "连接超时，服务可能暂时不可用。"
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                message = "无法连接到服务器，服务可能已下线。"
            default:
                break
            }
        }
        showError(message)
    }
}

// MARK: - WKUIDelegate

extension ViewController: WKUIDelegate {

    /// 页面里 `target="_blank"` 或 `window.open()` 的链接，在当前 WebView 内打开，避免点了没反应
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
