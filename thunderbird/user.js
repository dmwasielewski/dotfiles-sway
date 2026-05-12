// Force read receipt request for all outgoing emails
user_pref("mail.mdn.receipt.request_policy", 4);

// Force light mode in Thunderbird
user_pref("mail.dark-reader.enabled", false);
user_pref("layout.css.prefers-color-scheme.content-override", 1);
// Enable custom CSS in Thunderbird
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Use 24-hour time format
user_pref("intl.regional_prefs.use_os_locales", true);

// Force 24-hour time in message list
user_pref("mail.ui.display.dateformat.today", 2);

// Suppress donation popup — Thunderbird 134+ uses in-app notifications
user_pref("mail.inappnotifications.enabled", false);

// Permanently suppress start page (which shows donation content)
user_pref("mailnews.start_page_override.mstone", "ignore");

// Disable the start page entirely (empty message pane shows donation by default)
user_pref("mailnews.start_page.enabled", false);

// Skip start page — open Inbox with first email selected
user_pref("messenger.startup.action", 1);
