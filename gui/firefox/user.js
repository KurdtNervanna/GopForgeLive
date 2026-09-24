// Firefox prefs for the GopForge Live kiosk: an offline, single-purpose window.
// Copied into a throw-away profile on every boot by gui/session.sh.

// no first-run / what's-new / default-browser nags
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("datareporting.policy.firstRunURL", "");

// no telemetry, updates, crash reporting, studies (the disk is offline anyway)
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("app.normandy.enabled", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("browser.crashReports.unsubmittedCheck.autoSubmit2", false);
user_pref("breakpad.reportURL", "");

// no network probes / remote services
user_pref("network.captive-portal-service.enabled", false);
user_pref("network.connectivity-service.enabled", false);
user_pref("browser.safebrowsing.malware.enabled", false);
user_pref("browser.safebrowsing.phishing.enabled", false);
user_pref("browser.safebrowsing.downloads.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.translations.enable", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("extensions.update.enabled", false);
user_pref("browser.search.update", false);
user_pref("services.settings.server", "http://127.0.0.1:9/");
user_pref("network.dns.disablePrefetch", true);
user_pref("network.prefetch-next", false);

// no session restore or close prompts; single window, no popups
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.sessionstore.max_resumed_crashes", 0);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.warnOnQuit", false);
user_pref("dom.disable_open_during_load", true);
user_pref("browser.link.open_newwindow", 1);

// quiet chrome
user_pref("browser.fullscreen.autohide", true);
user_pref("full-screen-api.warning.timeout", 0);
user_pref("ui.systemUsesDarkTheme", 1);
user_pref("layout.css.prefers-color-scheme.content-override", 0);
user_pref("gfx.webrender.software", true);
user_pref("media.hardware-video-decoding.enabled", false);
