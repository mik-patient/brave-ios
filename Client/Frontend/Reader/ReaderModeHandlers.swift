/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import GCDWebServers
import Shared

public struct ReaderModeHandlers {
  static let readerModeStyleHash = "sha256-L2W8+0446ay9/L1oMrgucknQXag570zwgQrHwE68qbQ="

  static var readerModeCache: ReaderModeCache = DiskReaderModeCache.sharedInstance

  public static func register(_ webServer: WebServer, profile: Profile) {
    // Register our fonts and css, which we want to expose to web content that we present in the WebView
    webServer.registerMainBundleResourcesOfType("ttf", module: "reader-mode/fonts")
    webServer.registerMainBundleResourcesOfType("otf", module: "reader-mode/fonts")
    webServer.registerMainBundleResource("Reader.css", module: "reader-mode/styles")

    // Register a handler that simply lets us know if a document is in the cache or not. This is called from the
    // reader view interstitial page to find out when it can stop showing the 'Loading...' page and instead load
    // the readerized content.
    webServer.registerHandlerForMethod("GET", module: "reader-mode", resource: "page-exists") { (request: GCDWebServerRequest?) -> GCDWebServerResponse? in
      guard let query = request?.query, let stringURL = query["url"],
        let url = URL(string: stringURL)
      else {
        return GCDWebServerResponse(statusCode: 500)
      }

      let status = readerModeCache.contains(url) ? 200 : 404
      return GCDWebServerResponse(statusCode: status)
    }

    // Register the handler that accepts /reader-mode/page?url=http://www.example.com requests.
    webServer.registerHandlerForMethod("GET", module: "reader-mode", resource: "page") { (request: GCDWebServerRequest?) -> GCDWebServerResponse? in
      if let query = request?.query, let url = query["url"] {
        if let url = URL(string: url), url.isWebPage() {
          do {
            let readabilityResult = try readerModeCache.get(url)
            // We have this page in our cache, so we can display it. Just grab the correct style from the
            // profile and then generate HTML from the Readability results.
            var readerModeStyle = DefaultReaderModeStyle
            if let dict = profile.prefs.dictionaryForKey(ReaderModeProfileKeyStyle) {
              if let style = ReaderModeStyle(dict: dict) {
                readerModeStyle = style
              }
            }

            // Must generate a unique nonce, every single time as per Content-Policy spec.
            let setTitleNonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")

            if let html = ReaderModeUtils.generateReaderContent(
              readabilityResult, initialStyle: readerModeStyle,
              titleNonce: setTitleNonce),
              let response = GCDWebServerDataResponse(html: html) {
              // Apply a Content Security Policy that disallows everything except images from anywhere and fonts and css from our internal server
              response.setValue("default-src 'none'; img-src *; style-src http://localhost:* '\(readerModeStyleHash)'; font-src http://localhost:*; script-src 'nonce-\(setTitleNonce)'", forAdditionalHeader: "Content-Security-Policy")
              return response
            }
          } catch _ {
            // This page has not been converted to reader mode yet. This happens when you for example add an
            // item via the app extension and the application has not yet had a change to readerize that
            // page in the background.
            //
            // What we do is simply queue the page in the ReadabilityService and then show our loading
            // screen, which will periodically call page-exists to see if the readerized content has
            // become available.
            ReadabilityService.sharedInstance.process(url, cache: readerModeCache)
            if let readerViewLoadingPath = Bundle.module.path(forResource: "ReaderViewLoading", ofType: "html") {
              do {
                var contents = try String(contentsOfFile: readerViewLoadingPath)
                let mapping = [
                  "%message_handler%": LocalRequestHelper.messageHandlerName,
                  "%ORIGINAL-URL%": url.absoluteString,
                  "%LOADING-TEXT%": Strings.readerModeLoadingContentDisplayText,
                  "%LOADING-FAILED-TEXT%": Strings.readerModePageCantShowDisplayText,
                  "%LOAD-ORIGINAL-TEXT%": Strings.readerModeLoadOriginalLinkText
                ]
                
                mapping.forEach {
                  contents = contents.replacingOccurrences(of: $0.key, with: $0.value)
                }
                
                return GCDWebServerDataResponse(html: contents)
              } catch {
                assertionFailure("CANNOT LOAD  ReaderViewLoading.html: \(error)")
              }
            }
          }
        }
      }

      return GCDWebServerDataResponse(html: Strings.readerModeErrorConvertDisplayText)  // TODO Needs a proper error page
    }
  }
}
