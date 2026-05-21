import 'package:flutter/widgets.dart';

import '../providers/locale_provider.dart';
import 'strings_ar.dart';
import 'strings_ckb.dart';
import 'strings_en.dart';

/// Central string lookup for the app's UI text.
///
/// Backed by plain Dart maps (no codegen). Each [AppLanguage] has a
/// `Map<String, String>` of `key -> translation`. English is the
/// source of truth and the fallback for any key a translation file
/// has not filled in yet, so a missing Arabic/Kurdish key degrades
/// to English instead of crashing.
///
/// Usage in a widget:
///
/// ```dart
/// Text(context.t.settings)            // simple key
/// Text(context.t.helloName('Sara'))   // parameterized helper
/// ```
class AppStrings {
  const AppStrings(this.language);

  final AppLanguage language;

  static const Map<AppLanguage, Map<String, String>> _tables = {
    AppLanguage.english: enStrings,
    AppLanguage.arabic: arStrings,
    AppLanguage.kurdish: ckbStrings,
  };

  /// Raw key lookup with English fallback. Falls back to the key
  /// itself only if English is also missing it (developer error).
  String _get(String key) {
    return _tables[language]?[key] ?? enStrings[key] ?? key;
  }

  /// Substitutes `{name}`, `{count}`, … placeholders in a translated
  /// string. Unknown placeholders are left untouched.
  String _fmt(String key, Map<String, Object?> args) {
    var out = _get(key);
    args.forEach((name, value) {
      out = out.replaceAll('{$name}', '$value');
    });
    return out;
  }

  // ──────────────────────────────────────────────────────────────
  // Generic / common
  // ──────────────────────────────────────────────────────────────
  String get appName => _get('app_name');
  String get ok => _get('ok');
  String get cancel => _get('cancel');
  String get save => _get('save');
  String get delete => _get('delete');
  String get edit => _get('edit');
  String get done => _get('done');
  String get next => _get('next');
  String get back => _get('back');
  String get skip => _get('skip');
  String get retry => _get('retry');
  String get close => _get('close');
  String get confirm => _get('confirm');
  String get yes => _get('yes');
  String get no => _get('no');
  String get search => _get('search');
  String get loading => _get('loading');
  String get errorGeneric => _get('error_generic');
  String get noInternet => _get('no_internet');
  String get send => _get('send');
  String get share => _get('share');
  String get report => _get('report');
  String get block => _get('block');
  String get unblock => _get('unblock');
  String get remove => _get('remove');
  String get add => _get('add');
  String get seeAll => _get('see_all');
  String get viewAll => _get('view_all');
  String get more => _get('more');
  String get continueLabel => _get('continue_label');
  String get submit => _get('submit');
  String get update => _get('update');
  String get apply => _get('apply');
  String get clear => _get('clear');
  String get copy => _get('copy');
  String get copied => _get('copied');
  String get emptyHere => _get('empty_here');

  // ──────────────────────────────────────────────────────────────
  // Auth — login / signup / onboarding / OTP / forgot password
  // ──────────────────────────────────────────────────────────────
  String get login => _get('login');
  String get logout => _get('logout');
  String get signup => _get('signup');
  String get signIn => _get('sign_in');
  String get signUp => _get('sign_up');
  String get email => _get('email');
  String get password => _get('password');
  String get confirmPassword => _get('confirm_password');
  String get forgotPassword => _get('forgot_password');
  String get resetPassword => _get('reset_password');
  String get createAccount => _get('create_account');
  String get welcomeBack => _get('welcome_back');
  String get continueWithGoogle => _get('continue_with_google');
  String get continueWithApple => _get('continue_with_apple');
  String get dontHaveAccount => _get('dont_have_account');
  String get alreadyHaveAccount => _get('already_have_account');
  String get fullName => _get('full_name');
  String get username => _get('username');
  String get phoneNumber => _get('phone_number');
  String get otpTitle => _get('otp_title');
  String get otpSubtitle => _get('otp_subtitle');
  String get resendCode => _get('resend_code');
  String get verify => _get('verify');
  String get enterEmail => _get('enter_email');
  String get enterPassword => _get('enter_password');
  String get invalidEmail => _get('invalid_email');
  String get passwordTooShort => _get('password_too_short');
  String get passwordsDontMatch => _get('passwords_dont_match');
  String get resetLinkSent => _get('reset_link_sent');
  String get getStarted => _get('get_started');

  // ──────────────────────────────────────────────────────────────
  // Bottom navigation
  // ──────────────────────────────────────────────────────────────
  String get navHome => _get('nav_home');
  String get navEvents => _get('nav_events');
  String get navMessages => _get('nav_messages');
  String get navProfile => _get('nav_profile');
  String get navNotifications => _get('nav_notifications');

  // ──────────────────────────────────────────────────────────────
  // Home / feed / posts
  // ──────────────────────────────────────────────────────────────
  String get home => _get('home');
  String get feed => _get('feed');
  String get createPost => _get('create_post');
  String get post => _get('post');
  String get whatsOnYourMind => _get('whats_on_your_mind');
  String get like => _get('like');
  String get comment => _get('comment');
  String get comments => _get('comments');
  String get likes => _get('likes');
  String get addComment => _get('add_comment');
  String get writeComment => _get('write_comment');
  String get noComments => _get('no_comments');
  String get noPosts => _get('no_posts');
  String get reply => _get('reply');
  String get replies => _get('replies');
  String get viewComments => _get('view_comments');
  String get sharePost => _get('share_post');
  String get savePost => _get('save_post');
  String get deletePost => _get('delete_post');
  String get editPost => _get('edit_post');
  String get reportPost => _get('report_post');
  String get postDeleted => _get('post_deleted');
  String get justNow => _get('just_now');
  String likesCount(Object count) => _fmt('likes_count', {'count': count});
  String commentsCount(Object count) =>
      _fmt('comments_count', {'count': count});

  // ──────────────────────────────────────────────────────────────
  // Stories
  // ──────────────────────────────────────────────────────────────
  String get story => _get('story');
  String get stories => _get('stories');
  String get addToStory => _get('add_to_story');
  String get yourStory => _get('your_story');
  String get viewStory => _get('view_story');
  String get replyToStory => _get('reply_to_story');
  String get storyExpired => _get('story_expired');

  // ──────────────────────────────────────────────────────────────
  // Messaging / chat
  // ──────────────────────────────────────────────────────────────
  String get messages => _get('messages');
  String get message => _get('message');
  String get newMessage => _get('new_message');
  String get typeMessage => _get('type_message');
  String get typing => _get('typing');
  String get online => _get('online');
  String get offline => _get('offline');
  String get lastSeen => _get('last_seen');
  String get noMessages => _get('no_messages');
  String get sayHi => _get('say_hi');
  String get sent => _get('sent');
  String get delivered => _get('delivered');
  String get read => _get('read');
  String get deleteMessage => _get('delete_message');
  String get deleteChat => _get('delete_chat');
  String get muteNotifications => _get('mute_notifications');
  String get messageRequest => _get('message_request');
  String get acceptRequest => _get('accept_request');
  String get declineRequest => _get('decline_request');
  String get photo => _get('photo');
  String get video => _get('video');
  String get voiceMessage => _get('voice_message');
  String get attachment => _get('attachment');

  // ──────────────────────────────────────────────────────────────
  // Profile
  // ──────────────────────────────────────────────────────────────
  String get profile => _get('profile');
  String get editProfile => _get('edit_profile');
  String get followers => _get('followers');
  String get following => _get('following');
  String get follow => _get('follow');
  String get unfollow => _get('unfollow');
  String get followBack => _get('follow_back');
  String get requested => _get('requested');
  String get posts => _get('posts');
  String get bio => _get('bio');
  String get website => _get('website');
  String get location => _get('location');
  String get joinedOn => _get('joined_on');
  String get profileVisitors => _get('profile_visitors');
  String get noFollowers => _get('no_followers');
  String get noFollowing => _get('no_following');
  String get blockUser => _get('block_user');
  String get reportUser => _get('report_user');
  String get privateAccount => _get('private_account');
  String get thisAccountIsPrivate => _get('this_account_is_private');
  String followersCount(Object count) =>
      _fmt('followers_count', {'count': count});

  // ──────────────────────────────────────────────────────────────
  // Events
  // ──────────────────────────────────────────────────────────────
  String get events => _get('events');
  String get event => _get('event');
  String get upcomingEvents => _get('upcoming_events');
  String get pastEvents => _get('past_events');
  String get eventDetails => _get('event_details');
  String get registerForEvent => _get('register_for_event');
  String get registered => _get('registered');
  String get eventChat => _get('event_chat');
  String get eventLocation => _get('event_location');
  String get eventDate => _get('event_date');
  String get eventDeadline => _get('event_deadline');
  String get noEvents => _get('no_events');
  String get eventUnavailable => _get('event_unavailable');
  String get joinEvent => _get('join_event');

  // ──────────────────────────────────────────────────────────────
  // Notifications
  // ──────────────────────────────────────────────────────────────
  String get notifications => _get('notifications');
  String get noNotifications => _get('no_notifications');
  String get markAllRead => _get('mark_all_read');
  String get newNotification => _get('new_notification');

  // ──────────────────────────────────────────────────────────────
  // Settings
  // ──────────────────────────────────────────────────────────────
  String get settings => _get('settings');
  String get account => _get('account');
  String get appearance => _get('appearance');
  String get languageLabel => _get('language');
  String get appLanguage => _get('app_language');
  String get chooseLanguage => _get('choose_language');
  String get darkMode => _get('dark_mode');
  String get lightMode => _get('light_mode');
  String get theme => _get('theme');
  String get safety => _get('safety');
  String get privacy => _get('privacy');
  String get dangerZone => _get('danger_zone');
  String get changeEmail => _get('change_email');
  String get changePassword => _get('change_password');
  String get setPassword => _get('set_password');
  String get blockedUsers => _get('blocked_users');
  String get deleteAccount => _get('delete_account');
  String get contactUs => _get('contact_us');
  String get aboutApp => _get('about_app');
  String get version => _get('version');
  String get translationLanguage => _get('translation_language');
  String get notificationSettings => _get('notification_settings');
  String get shareApp => _get('share_app');
  String get languageChanged => _get('language_changed');

  // ──────────────────────────────────────────────────────────────
  // Translation feature
  // ──────────────────────────────────────────────────────────────
  String get translate => _get('translate');
  String get translation => _get('translation');
  String get translated => _get('translated');
  String get showOriginal => _get('show_original');
  String get savedTranslations => _get('saved_translations');
  String get seeTranslation => _get('see_translation');

  // ──────────────────────────────────────────────────────────────
  // Admin
  // ──────────────────────────────────────────────────────────────
  String get admin => _get('admin');
  String get dashboard => _get('dashboard');
  String get manageUsers => _get('manage_users');
  String get managePosts => _get('manage_posts');
  String get manageEvents => _get('manage_events');
  String get reports => _get('reports');
  String get blacklist => _get('blacklist');
  String get contactRequests => _get('contact_requests');
  String get errorReports => _get('error_reports');

  // ──────────────────────────────────────────────────────────────
  // Errors / dialogs
  // ──────────────────────────────────────────────────────────────
  String get areYouSure => _get('are_you_sure');
  String get actionCannotBeUndone => _get('action_cannot_be_undone');
  String get somethingWentWrong => _get('something_went_wrong');
  String get tryAgain => _get('try_again');
  String get permissionDenied => _get('permission_denied');
  String get cameraPermissionNeeded => _get('camera_permission_needed');
  String get galleryPermissionNeeded => _get('gallery_permission_needed');
  String get micPermissionNeeded => _get('mic_permission_needed');
  String get locationPermissionNeeded => _get('location_permission_needed');

  // ──────────────────────────────────────────────────────────────
  // ── AUTH SCREENS (added) ──
  // ──────────────────────────────────────────────────────────────
  String get loginSubtitle => _get('login_subtitle');
  String get loginUsernameOrEmail => _get('login_username_or_email');
  String get loginEnterUsernameOrEmail =>
      _get('login_enter_username_or_email');
  String get loginMin6Chars => _get('login_min_6_chars');
  String get loginOr => _get('login_or');
  String get loginSigningIn => _get('login_signing_in');
  String get signupSubtitle => _get('signup_subtitle');
  String get signupEnterUsername => _get('signup_enter_username');
  String get signupEnterValidEmail => _get('signup_enter_valid_email');
  String get signupSignInWithFacebook =>
      _get('signup_sign_in_with_facebook');
  String get forgotPasswordSubtitle => _get('forgot_password_subtitle');
  String get forgotPasswordEmailSent => _get('forgot_password_email_sent');
  String get forgotPasswordCheckInbox => _get('forgot_password_check_inbox');
  String get forgotPasswordBackToLogin =>
      _get('forgot_password_back_to_login');
  String get forgotPasswordEmailAddress =>
      _get('forgot_password_email_address');
  String get forgotPasswordEnterEmail => _get('forgot_password_enter_email');
  String get forgotPasswordEnterValidEmail =>
      _get('forgot_password_enter_valid_email');
  String get forgotPasswordSendResetLink =>
      _get('forgot_password_send_reset_link');
  String get otpEnterCode => _get('otp_enter_code');
  String otpCodeSentTo(Object destination) =>
      _fmt('otp_code_sent_to', {'destination': destination});
  String get otpDidntGet => _get('otp_didnt_get');
  String get otpResend => _get('otp_resend');
  String get onboardingSetupProfile => _get('onboarding_setup_profile');
  String get onboardingGender => _get('onboarding_gender');
  String get onboardingGenderMale => _get('onboarding_gender_male');
  String get onboardingGenderFemale => _get('onboarding_gender_female');
  String get onboardingGenderNonBinary =>
      _get('onboarding_gender_non_binary');
  String get onboardingGenderOther => _get('onboarding_gender_other');
  String get onboardingMin3Chars => _get('onboarding_min_3_chars');
  String get onboardingAboutYou => _get('onboarding_about_you');
  String get onboardingOptional => _get('onboarding_optional');
  String get onboardingAboutYouDesc => _get('onboarding_about_you_desc');
  String get onboardingWhereAreYou => _get('onboarding_where_are_you');
  String get onboardingGpsSet => _get('onboarding_gps_set');
  String get onboardingLocationDesc => _get('onboarding_location_desc');
  String get onboardingUpdateLocation =>
      _get('onboarding_update_location');
  String get onboardingUseMyLocation => _get('onboarding_use_my_location');
  String get onboardingCity => _get('onboarding_city');
  String get onboardingCityAutofilled =>
      _get('onboarding_city_autofilled');
  String get onboardingCityHint => _get('onboarding_city_hint');
  String get splashAppName => _get('splash_app_name');

  // ──────────────────────────────────────────────────────────────
  // ── HOME/FEED SCREENS (added) ──
  // ──────────────────────────────────────────────────────────────
  String get homeFeed => _get('home_feed');
  String get homeTravelShort => _get('home_travel_short');
  String get homeTravelMode => _get('home_travel_mode');
  String get homeDiscuss => _get('home_discuss');
  String homeErrorPrefix(Object error) =>
      _fmt('home_error_prefix', {'error': error});
  String get homeNoDiscussThreads => _get('home_no_discuss_threads');
  String get homeNoMatchingQuestions => _get('home_no_matching_questions');
  String get homeNoPostsCreateFirst => _get('home_no_posts_create_first');
  String get homeQuestionActions => _get('home_question_actions');
  String get homeDeleteQuestionTitle => _get('home_delete_question_title');
  String get homeDeleteQuestionBody => _get('home_delete_question_body');
  String get homeQuestionDeleted => _get('home_question_deleted');
  String homeCouldNotDelete(Object error) =>
      _fmt('home_could_not_delete', {'error': error});
  String get homeReportQuestionMenu => _get('home_report_question_menu');
  String get homeDeleteQuestionMenu => _get('home_delete_question_menu');
  String get homeQuestionLabel => _get('home_question_label');
  String get homeDiscussionLabel => _get('home_discussion_label');
  String homeAnswersCount(Object count) =>
      _fmt('home_answers_count', {'count': count});
  String homeHelpfulCount(Object count) =>
      _fmt('home_helpful_count', {'count': count});
  String get homeWriteAnswer => _get('home_write_answer');
  String get homePickReasonQuestion => _get('home_pick_reason_question');
  String get homeExtraDetailsOptional => _get('home_extra_details_optional');
  String get homeSendReport => _get('home_send_report');
  String get homeReportSentAdmins => _get('home_report_sent_admins');
  String homeCouldNotReportQuestion(Object error) =>
      _fmt('home_could_not_report_question', {'error': error});
  String get homeQaPromptTitle => _get('home_qa_prompt_title');
  String get homeQaPromptSubtitle => _get('home_qa_prompt_subtitle');
  String get homeAsk => _get('home_ask');
  String get homeFeedPromptTitle => _get('home_feed_prompt_title');
  String get homeFeedPromptSubtitle => _get('home_feed_prompt_subtitle');
  String get homeTravelPromptTitle => _get('home_travel_prompt_title');
  String get homeTravelPromptSubtitle => _get('home_travel_prompt_subtitle');
  String get homeSearchQuestionsUsers => _get('home_search_questions_users');
  String get homeClearSearch => _get('home_clear_search');
  String get homeSearchPosts => _get('home_search_posts');
  String get homeNoMatchingPosts => _get('home_no_matching_posts');
  String get homeAskCommunity => _get('home_ask_community');
  String get homeWriteQuestionFirst => _get('home_write_question_first');
  String get homeWhatsYourQuestion => _get('home_whats_your_question');
  String get homeAddMoreContext => _get('home_add_more_context');
  String get homePostQuestion => _get('home_post_question');
  String get homeSearchPlace => _get('home_search_place');
  String get homeLocationServicesOff => _get('home_location_services_off');
  String get travelLocationOffBanner => _get('travel_location_off_banner');
  String get travelEnableLocation => _get('travel_enable_location');
  String get homeOpenSettings => _get('home_open_settings');
  String get homeLocationPermissionDeniedTravel =>
      _get('home_location_permission_denied_travel');
  String get homeLocationPermissionBlocked =>
      _get('home_location_permission_blocked');
  String get homeAppSettings => _get('home_app_settings');
  String get homeCouldntGetLocation => _get('home_couldnt_get_location');
  String get homeMaintenanceMode => _get('home_maintenance_mode');
  String get homeAllPlaces => _get('home_all_places');
  String get homeNearby => _get('home_nearby');
  String homeNearbyCity(Object city) =>
      _fmt('home_nearby_city', {'city': city});
  String get homeSearchPlaceInPosts => _get('home_search_place_in_posts');
  String get homeCouldNotLoadPlaces => _get('home_could_not_load_places');
  String get homeSearchPlaceTitle => _get('home_search_place_title');
  String get homeNoPlacesFound => _get('home_no_places_found');
  String get homeRecent => _get('home_recent');
  String get homeResults => _get('home_results');
  String get homePopularTravelPosts => _get('home_popular_travel_posts');
  String get homeUnknownCity => _get('home_unknown_city');
  String get homeUseCurrentLocation => _get('home_use_current_location');
  String get headerAppTitle => _get('header_app_title');
  String get postNotFound => _get('post_not_found');
  String get commentNoCommentsFirst => _get('comment_no_comments_first');
  String get commentHideReplies => _get('comment_hide_replies');
  String commentReplyingTo(Object username) =>
      _fmt('comment_replying_to', {'username': username});
  String commentReplyToHint(Object username) =>
      _fmt('comment_reply_to_hint', {'username': username});
  String get commentAddCommentHint => _get('comment_add_comment_hint');
  String commentTranslateTo(Object language) =>
      _fmt('comment_translate_to', {'language': language});
  String get commentTranslationCopied => _get('comment_translation_copied');
  String get qaThreadTitle => _get('qa_thread_title');
  String qaCouldNotLoadAnswers(Object error) =>
      _fmt('qa_could_not_load_answers', {'error': error});
  String get qaUntitledQuestion => _get('qa_untitled_question');
  String get qaQuestionLabel => _get('qa_question_label');
  String get qaViewOriginalPost => _get('qa_view_original_post');
  String get qaEditQuestion => _get('qa_edit_question');
  String get qaEditQuestionHint => _get('qa_edit_question_hint');
  String get qaAnswersLabel => _get('qa_answers_label');
  String qaCouldNotSaveReaction(Object error) =>
      _fmt('qa_could_not_save_reaction', {'error': error});
  String get qaWriteAnswerHint => _get('qa_write_answer_hint');
  String get qaWriteReplyHint => _get('qa_write_reply_hint');
  String get createPostNewPost => _get('create_post_new_post');
  String get createPostCaptionHint => _get('create_post_caption_hint');
  String get createPostPlace => _get('create_post_place');
  String get createPostPlaceNameHint => _get('create_post_place_name_hint');
  String get createPostCityHint => _get('create_post_city_hint');
  String get createPostUseCurrentLocation =>
      _get('create_post_use_current_location');
  String get createPostLocateOnMap => _get('create_post_locate_on_map');
  String get createPostPhotoFromGallery =>
      _get('create_post_photo_from_gallery');
  String get createPostTakeAPhoto => _get('create_post_take_a_photo');
  String get createPostVideoFromGallery =>
      _get('create_post_video_from_gallery');
  String get createPostRecordAVideo => _get('create_post_record_a_video');
  String get createPostVideoSizeLimit => _get('create_post_video_size_limit');
  String get createPostFollowersOnly => _get('create_post_followers_only');
  String get createPostPublic => _get('create_post_public');
  String get createPostCurrentLocation =>
      _get('create_post_current_location');
  String get createPostYou => _get('create_post_you');
  String get createPostLocationServicesOff =>
      _get('create_post_location_services_off');
  String get createPostLocationPermissionDenied =>
      _get('create_post_location_permission_denied');
  String get createPostTypePlaceFirst => _get('create_post_type_place_first');
  String createPostNoCoordinates(Object query) =>
      _fmt('create_post_no_coordinates', {'query': query});
  String createPostLookupFailed(Object error) =>
      _fmt('create_post_lookup_failed', {'error': error});
  String get createPostAddCaptionImageVideo =>
      _get('create_post_add_caption_image_video');
  String get createPostCouldNotReadVideo =>
      _get('create_post_could_not_read_video');
  String createPostVideoTooLarge(Object size) =>
      _fmt('create_post_video_too_large', {'size': size});
  String get createPostPublishedWithContent =>
      _get('create_post_published_with_content');
  String get createPostPublished => _get('create_post_published');
  String createPostCouldNotPublish(Object error) =>
      _fmt('create_post_could_not_publish', {'error': error});
  String get postCardRemovedFromSaved => _get('post_card_removed_from_saved');
  String get postCardSavedToProfile => _get('post_card_saved_to_profile');
  String postCardCouldNotSave(Object error) =>
      _fmt('post_card_could_not_save', {'error': error});
  String get postCardRepostRemoved => _get('post_card_repost_removed');
  String get postCardRepostedToProfile =>
      _get('post_card_reposted_to_profile');
  String postCardCouldNotRepost(Object error) =>
      _fmt('post_card_could_not_repost', {'error': error});
  String get postCardSendTo => _get('post_card_send_to');
  String get postCardNoConversations => _get('post_card_no_conversations');
  String postCardSharedTo(Object username) =>
      _fmt('post_card_shared_to', {'username': username});
  String get postCardEditCaption => _get('post_card_edit_caption');
  String get postCardMakePublic => _get('post_card_make_public');
  String get postCardMakeFollowersOnly =>
      _get('post_card_make_followers_only');
  String get postCardCaptionHint => _get('post_card_caption_hint');
  String get postCardDeletePostTitle => _get('post_card_delete_post_title');
  String get postCardCannotBeUndone => _get('post_card_cannot_be_undone');
  String postCardFailed(Object error) =>
      _fmt('post_card_failed', {'error': error});
  String get postCardReportPost => _get('post_card_report_post');
  String get postCardPickReasonPost => _get('post_card_pick_reason_post');
  String get postCardReportSentAdmins => _get('post_card_report_sent_admins');
  String get postCardReadMore => _get('post_card_read_more');
  String get postCardShowLess => _get('post_card_show_less');
  String get postCardTurnOnLocation => _get('post_card_turn_on_location');
  String get discussAskTitle => _get('discuss_ask_title');
  String get discussAskHint => _get('discuss_ask_hint');
  String get discussAskAction => _get('discuss_ask_action');
  String get postCardDiscussThisPost => _get('post_card_discuss_this_post');
  String get postCardViewInDiscuss => _get('post_card_view_in_discuss');
  String get postCardDiscussCreated => _get('post_card_discuss_created');
  String postCardDiscussFailed(Object error) =>
      _fmt('post_card_discuss_failed', {'error': error});
  String get postCardAddToStory => _get('post_card_add_to_story');
  String get postCardAddToStorySub => _get('post_card_add_to_story_sub');
  String get postCardAddedToStory => _get('post_card_added_to_story');
  String postCardStoryFailed(Object error) =>
      _fmt('post_card_story_failed', {'error': error});

  // ── CHAT/MESSAGING SCREENS (added) ──
  String get messagingRestrictedGroup => _get('messaging_restricted_group');
  String get onlyAdminsCanMessage => _get('only_admins_can_message');
  String failedToSendMessage(Object error) =>
      _fmt('failed_to_send_message', {'error': error});
  String get mediaSharingDisabledGroup => _get('media_sharing_disabled_group');
  String get cannotSendMediaGroup => _get('cannot_send_media_group');
  String get cannotSendVoiceGroup => _get('cannot_send_voice_group');
  String get fileLabel => _get('file_label');
  String get fileSubtitle => _get('file_subtitle');
  String get locationLabel => _get('location_label');
  String get locationSubtitle => _get('location_subtitle');
  String get locationServicesOff => _get('location_services_off');
  String get locationPermDenied => _get('location_perm_denied');
  String get locationShared => _get('location_shared');
  String couldNotShareLocation(Object error) =>
      _fmt('could_not_share_location', {'error': error});
  String get videoTooLarge => _get('video_too_large');
  String couldNotOpenFilePicker(Object error) =>
      _fmt('could_not_open_file_picker', {'error': error});
  String get couldNotReadFile => _get('could_not_read_file');
  String get fileTooLarge => _get('file_too_large');
  String get microphonePermissionDenied =>
      _get('microphone_permission_denied');
  String get failedToRecordVoice => _get('failed_to_record_voice');
  String get recordingFileNotFound => _get('recording_file_not_found');
  String get voiceRecordingEmpty => _get('voice_recording_empty');
  String get voiceMessageTooShort => _get('voice_message_too_short');
  String get failedUploadVoiceEmpty => _get('failed_upload_voice_empty');
  String voiceUploadFailed(Object error) =>
      _fmt('voice_upload_failed', {'error': error});
  String get translationAutoDescription =>
      _get('translation_auto_description');
  String get autoTranslateIncoming => _get('auto_translate_incoming');
  String get translateInto => _get('translate_into');
  String autoTranslateOnTooltip(Object lang) =>
      _fmt('auto_translate_on_tooltip', {'lang': lang});
  String get translationSettingsTooltip =>
      _get('translation_settings_tooltip');
  String get groupSettings => _get('group_settings');
  String get sharedMedia => _get('shared_media');
  String get chatOptions => _get('chat_options');
  String get autoDeleteMessages => _get('auto_delete_messages');
  String membersCount(Object count) =>
      _fmt('members_count', {'count': count});
  String get sayHello => _get('say_hello');
  String get youveBlockedUser => _get('youve_blocked_user');
  String get cantReplyConversation => _get('cant_reply_conversation');
  String get attach => _get('attach');
  String get writeAMessage => _get('write_a_message');
  String get autoDeleteOff => _get('auto_delete_off');
  String get autoDeleteOneDay => _get('auto_delete_one_day');
  String get autoDeleteOneWeek => _get('auto_delete_one_week');
  String get autoDeleteOneMonth => _get('auto_delete_one_month');
  String get autoDeletePeriodDescription =>
      _get('auto_delete_period_description');
  String get autoDeleteTurnedOff => _get('auto_delete_turned_off');
  String autoDeleteSet(Object period) =>
      _fmt('auto_delete_set', {'period': period});
  String failedWithError(Object error) =>
      _fmt('failed_with_error', {'error': error});
  String get deleteChatQuestion => _get('delete_chat_question');
  String get deleteChatBody => _get('delete_chat_body');
  String deleteFailed(Object error) =>
      _fmt('delete_failed', {'error': error});
  String recordingElapsed(Object time) =>
      _fmt('recording_elapsed', {'time': time});
  String get messageUnavailable => _get('message_unavailable');
  String get translationFailedRetry => _get('translation_failed_retry');
  String get translating => _get('translating');
  String get showTranslation => _get('show_translation');
  String translateToLang(Object lang) =>
      _fmt('translate_to_lang', {'lang': lang});
  String get translateChangeInSettings =>
      _get('translate_change_in_settings');
  String get showTranscript => _get('show_transcript');
  String get transcriptUnavailable => _get('transcript_unavailable');
  String translateVoiceToLang(Object lang) =>
      _fmt('translate_voice_to_lang', {'lang': lang});
  String get deleteForMe => _get('delete_for_me');
  String get deleteForEveryone => _get('delete_for_everyone');
  String get deleteForBoth => _get('delete_for_both');
  String get deleteForEveryoneQuestion => _get('delete_for_everyone_question');
  String get deleteForBothQuestion => _get('delete_for_both_question');
  String get deleteForMeQuestion => _get('delete_for_me_question');
  String get deleteForEveryoneBody => _get('delete_for_everyone_body');
  String get deleteForMeBody => _get('delete_for_me_body');
  String get messageDeletedEveryone => _get('message_deleted_everyone');
  String get messageDeletedYou => _get('message_deleted_you');
  String get voiceTranscript => _get('voice_transcript');
  String translationWithLang(Object lang) =>
      _fmt('translation_with_lang', {'lang': lang});
  String get originalPostUnavailable => _get('original_post_unavailable');
  String get sharedPost => _get('shared_post');
  String memberOfEvent(Object title) =>
      _fmt('member_of_event', {'title': title});
  String get repliedToStory => _get('replied_to_story');
  String get sharedLocation => _get('shared_location');
  String get directions => _get('directions');
  String openFailed(Object error) => _fmt('open_failed', {'error': error});
  String sendToRecipient(Object name) =>
      _fmt('send_to_recipient', {'name': name});
  String get uploading => _get('uploading');
  String get sending => _get('sending');
  String get failedToSend => _get('failed_to_send');
  String get retryLabel => _get('retry_label');
  String get dismiss => _get('dismiss');
  String get attachmentDefaultName => _get('attachment_default_name');
  String get member => _get('member');
  String get someone => _get('someone');
  String get broadcastAMessage => _get('broadcast_a_message');
  String get adminLabel => _get('admin_label');
  String adminPrefix(Object name) => _fmt('admin_prefix', {'name': name});
  String senderAdmin(Object name) => _fmt('sender_admin', {'name': name});
  String get onlyAdminCanSend => _get('only_admin_can_send');
  String get eventMessagesNotEncrypted =>
      _get('event_messages_not_encrypted');
  String get eventGroup => _get('event_group');
  String get forwardTo => _get('forward_to');
  String get noChatsYet => _get('no_chats_yet');
  String forwardedTo(Object name) => _fmt('forwarded_to', {'name': name});
  String get images => _get('images');
  String get links => _get('links');
  String get voices => _get('voices');
  String get noImagesShared => _get('no_images_shared');
  String get noLinksShared => _get('no_links_shared');
  String get noVoiceMessages => _get('no_voice_messages');
  String get saveToGallery => _get('save_to_gallery');
  String get forwardToAnotherChat => _get('forward_to_another_chat');
  String get saving => _get('saving');
  String get savedToGallery => _get('saved_to_gallery');
  String saveFailed(Object error) => _fmt('save_failed', {'error': error});
  String get linkCopied => _get('link_copied');
  String get forward => _get('forward');
  String get goToMessage => _get('go_to_message');
  String secsVoiceMessage(Object secs) =>
      _fmt('secs_voice_message', {'secs': secs});
  String get searchWithDots => _get('search_with_dots');
  String get peopleYouFollow => _get('people_you_follow');
  String get noMatches => _get('no_matches');
  String get tapToStartChat => _get('tap_to_start_chat');
  String get user => _get('user');
  String get groupUppercase => _get('group_uppercase');
  String get eventUppercase => _get('event_uppercase');
  String allCount(Object count) => _fmt('all_count', {'count': count});
  String requestsCount(Object count) =>
      _fmt('requests_count', {'count': count});
  String get unmuteNotifications => _get('unmute_notifications');
  String get notificationsUnmuted => _get('notifications_unmuted');
  String get notificationsMuted => _get('notifications_muted');
  String get deleteGroup => _get('delete_group');
  String get removesGroupAndMessages => _get('removes_group_and_messages');
  String get removesGroupAllMessages => _get('removes_group_all_messages');
  String get removesConversationBoth => _get('removes_conversation_both');
  String get deleteThisChatQuestion => _get('delete_this_chat_question');
  String deleteChatGroupBody(Object name) =>
      _fmt('delete_chat_group_body', {'name': name});
  String deleteChatOneToOneBody(Object name) =>
      _fmt('delete_chat_one_to_one_body', {'name': name});
  String get chatDeleted => _get('chat_deleted');
  String failedToDelete(Object error) =>
      _fmt('failed_to_delete', {'error': error});
  String get deleteEventGroupQuestion => _get('delete_event_group_question');
  String deleteEventGroupBody(Object title) =>
      _fmt('delete_event_group_body', {'title': title});
  String get groupDeleted => _get('group_deleted');
  String newMessagesCount(Object count, Object label) =>
      _fmt('new_messages_count', {'count': count, 'label': label});
  String get removeFromFavorites => _get('remove_from_favorites');
  String get addToFavorites => _get('add_to_favorites');
  String get noStickersHere => _get('no_stickers_here');
  String get searchStickers => _get('search_stickers');
  String errorWithMessage(Object error) =>
      _fmt('error_with_message', {'error': error});
  String failedToSendSticker(Object error) =>
      _fmt('failed_to_send_sticker', {'error': error});

  // ── STORIES/NOTIF SCREENS (added) ──
  String get storySignInToLike => _get('story_sign_in_to_like');
  String storyFailedToggleLike(Object error) =>
      _fmt('story_failed_toggle_like', {'error': error});
  String get storyReplySent => _get('story_reply_sent');
  String get storySignInToReply => _get('story_sign_in_to_reply');
  String storyFailedSendReply(Object error) =>
      _fmt('story_failed_send_reply', {'error': error});
  String get storyDeleteTitle => _get('story_delete_title');
  String get storyDeleteBody => _get('story_delete_body');
  String storyDeleteFailed(Object error) =>
      _fmt('story_delete_failed', {'error': error});
  String storyViewsCount(Object count) =>
      _fmt('story_views_count', {'count': count});
  String storyViewCount(Object count) =>
      _fmt('story_view_count', {'count': count});
  String storyLikesCount(Object count) =>
      _fmt('story_likes_count', {'count': count});
  String storyLikeCount(Object count) =>
      _fmt('story_like_count', {'count': count});
  String get storyNoLikesYet => _get('story_no_likes_yet');
  String get storyNoViewsYet => _get('story_no_views_yet');
  String get storyReplyPrivatelyHint => _get('story_reply_privately_hint');
  String get storySignInBanner => _get('story_sign_in_banner');
  String get storyPublishedUploaded => _get('story_published_uploaded');
  String storyFailedPublish(Object error) =>
      _fmt('story_failed_publish', {'error': error});
  String get storyPublish => _get('story_publish');
  String get storyTapToViewPost => _get('story_tap_to_view_post');
  String get storyPhotoPermissionDenied =>
      _get('story_photo_permission_denied');
  String get storyOpenSettings => _get('story_open_settings');
  String get cameraNoCamerasFound => _get('camera_no_cameras_found');
  String cameraInitFailed(Object error) =>
      _fmt('camera_init_failed', {'error': error});
  String cameraCaptureFailed(Object error) =>
      _fmt('camera_capture_failed', {'error': error});
  String get featureStories => _get('feature_stories');
  String get notifNoActivity => _get('notif_no_activity');
  String get notifNoFollow => _get('notif_no_follow');
  String get notifNoEvent => _get('notif_no_event');
  String get notifCategoryActivity => _get('notif_category_activity');
  String get notifCategoryFollow => _get('notif_category_follow');
  String get notifCategoryEvent => _get('notif_category_event');
  String get notifFollowing => _get('notif_following');
  String get notifFollowBack => _get('notif_follow_back');
  String get notifFollow => _get('notif_follow');
  String get notifAccepted => _get('notif_accepted');
  String get notifRejected => _get('notif_rejected');
  String get notifProcessed => _get('notif_processed');
  String get notifReject => _get('notif_reject');
  String get notifAccept => _get('notif_accept');
  String notifStartedFollowing(Object username) =>
      _fmt('notif_started_following', {'username': username});
  String notifRequestedToFollow(Object username) =>
      _fmt('notif_requested_to_follow', {'username': username});
  String notifLikedYourPost(Object username) =>
      _fmt('notif_liked_your_post', {'username': username});
  String notifLikedYourComment(Object username) =>
      _fmt('notif_liked_your_comment', {'username': username});
  String notifCommentedOnPost(Object username) =>
      _fmt('notif_commented_on_post', {'username': username});
  String notifRepliedToComment(Object username) =>
      _fmt('notif_replied_to_comment', {'username': username});
  String notifAnsweredQuestion(Object username) =>
      _fmt('notif_answered_question', {'username': username});
  String notifRepliedToAnswer(Object username) =>
      _fmt('notif_replied_to_answer', {'username': username});
  String notifLikedYourAnswer(Object username) =>
      _fmt('notif_liked_your_answer', {'username': username});
  String notifDislikedYourAnswer(Object username) =>
      _fmt('notif_disliked_your_answer', {'username': username});
  String notifSentYouMessage(Object username) =>
      _fmt('notif_sent_you_message', {'username': username});
  String get notifEventApproved => _get('notif_event_approved');
  String get notifEventRejected => _get('notif_event_rejected');
  String notifAddedToEventGroup(Object username) =>
      _fmt('notif_added_to_event_group', {'username': username});
  String get notifRemovedFromEventGroup =>
      _get('notif_removed_from_event_group');
  String get notifNewEventPublished => _get('notif_new_event_published');
  String notifNewEventNamed(Object name) =>
      _fmt('notif_new_event_named', {'name': name});
  String notifAcceptedFollowRequest(Object username) =>
      _fmt('notif_accepted_follow_request', {'username': username});
  String get notifEventFallbackTitle => _get('notif_event_fallback_title');
  String get notifUserFallback => _get('notif_user_fallback');
  String get pollCreateTitle => _get('poll_create_title');
  String get pollAskQuestionHint => _get('poll_ask_question_hint');
  String pollOptionHint(Object number) =>
      _fmt('poll_option_hint', {'number': number});
  String get pollAddOption => _get('poll_add_option');
  String get pollVisibilityLabel => _get('poll_visibility_label');
  String get pollVisibilityPublic => _get('poll_visibility_public');
  String get pollVisibilityPublicDesc => _get('poll_visibility_public_desc');
  String get pollVisibilitySecret => _get('poll_visibility_secret');
  String get pollVisibilitySecretDesc => _get('poll_visibility_secret_desc');
  String get pollPostButton => _get('poll_post_button');
  String get pollSectionTitle => _get('poll_section_title');
  String get pollNewButton => _get('poll_new_button');
  String get pollBadgeSecret => _get('poll_badge_secret');
  String get pollBadgePublic => _get('poll_badge_public');
  String get pollCloseTooltip => _get('poll_close_tooltip');
  String pollVotesCount(Object count) =>
      _fmt('poll_votes_count', {'count': count});
  String pollVoteCount(Object count) =>
      _fmt('poll_vote_count', {'count': count});
  String get pollClosedSuffix => _get('poll_closed_suffix');

  // ── EVENTS SCREENS (added) ──
  String get eventsSearchPeople => _get('events_search_people');
  String get eventsSearchEvents => _get('events_search_events');
  String get eventsConnect => _get('events_connect');
  String get eventsFilterEventsByCity => _get('events_filter_events_by_city');
  String get eventsFilterByCity => _get('events_filter_by_city');
  String eventsFailedToOpenChat(Object error) =>
      _fmt('events_failed_to_open_chat', {'error': error});
  String get eventsActiveNow => _get('events_active_now');
  String get eventsJoinedJustNow => _get('events_joined_just_now');
  String eventsJoinedHoursAgo(Object hours) =>
      _fmt('events_joined_hours_ago', {'hours': hours});
  String eventsJoinedDaysAgo(Object days) =>
      _fmt('events_joined_days_ago', {'days': days});
  String eventsJoinedMonthsAgo(Object months) =>
      _fmt('events_joined_months_ago', {'months': months});
  String eventsJoinedYearsAgo(Object years) =>
      _fmt('events_joined_years_ago', {'years': years});
  String eventsPostsCount(Object count) =>
      _fmt('events_posts_count', {'count': count});
  String get eventsVeryActive => _get('events_very_active');
  String get eventsNoOneNearby => _get('events_no_one_nearby');
  String get eventsNoOneFromCity => _get('events_no_one_from_city');
  String get eventsBeFirstSayHi => _get('events_be_first_say_hi');
  String get eventsNoPeopleYet => _get('events_no_people_yet');
  String eventsNoFilterRightNow(Object filter) =>
      _fmt('events_no_filter_right_now', {'filter': filter});
  String eventsNoResultsFor(Object query) =>
      _fmt('events_no_results_for', {'query': query});
  String get eventsTryDifferentKeyword => _get('events_try_different_keyword');
  String eventsNoEventsMatching(Object query) =>
      _fmt('events_no_events_matching', {'query': query});
  String eventsNoEventsInCity(Object city) =>
      _fmt('events_no_events_in_city', {'city': city});
  String get eventsNewEventsAppearHere =>
      _get('events_new_events_appear_here');
  String get eventsTryDifferentKeywordLocation =>
      _get('events_try_different_keyword_location');
  String get eventsWantHostEvent => _get('events_want_host_event');
  String get eventsTapContactAdmin => _get('events_tap_contact_admin');
  String get eventsBecomeEventAdmin => _get('events_become_event_admin');
  String get eventsBecomeAdminBody => _get('events_become_admin_body');
  String get eventsEmailCopied => _get('events_email_copied');
  String get eventsForYou => _get('events_for_you');
  String get eventsSeeMore => _get('events_see_more');
  String eventsLocatingEvents(Object count) =>
      _fmt('events_locating_events', {'count': count});
  String eventsCouldNotBeMapped(Object count) =>
      _fmt('events_could_not_be_mapped', {'count': count});
  String get eventsDirections => _get('events_directions');
  String get eventsViewEvent => _get('events_view_event');
  String get eventsTravelMode => _get('events_travel_mode');
  String get eventsQuickStartGuide => _get('events_quick_start_guide');
  String get eventsSwitchTravelFeed => _get('events_switch_travel_feed');
  String get eventsSwitchTravelFeedBody =>
      _get('events_switch_travel_feed_body');
  String get eventsFilterByCityStep => _get('events_filter_by_city_step');
  String get eventsFilterByCityStepBody =>
      _get('events_filter_by_city_step_body');
  String get eventsSeeEventsOnMap => _get('events_see_events_on_map');
  String get eventsSeeEventsOnMapBody =>
      _get('events_see_events_on_map_body');
  String get eventsPlanYourTrip => _get('events_plan_your_trip');
  String get eventsPlanYourTripBody => _get('events_plan_your_trip_body');
  String get eventsGotIt => _get('events_got_it');
  String get eventGroupDeleteGroupTitle =>
      _get('event_group_delete_group_title');
  String get eventGroupDeleteGroupBody =>
      _get('event_group_delete_group_body');
  String eventGroupFailedToDelete(Object error) =>
      _fmt('event_group_failed_to_delete', {'error': error});
  String get eventGroupLeaveGroupTitle =>
      _get('event_group_leave_group_title');
  String get eventGroupLeaveGroupBody => _get('event_group_leave_group_body');
  String eventGroupFailed(Object error) =>
      _fmt('event_group_failed', {'error': error});
  String get eventGroupSettingsTitle => _get('event_group_settings_title');
  String get eventGroupPendingRequests =>
      _get('event_group_pending_requests');
  String get eventGroupMembers => _get('event_group_members');
  String get eventGroupAddUser => _get('event_group_add_user');
  String get eventGroupDeleteGroup => _get('event_group_delete_group');
  String get eventGroupLeaveGroup => _get('event_group_leave_group');
  String get eventGroupChat => _get('event_group_chat');
  String get eventGroupNoPendingRequests =>
      _get('event_group_no_pending_requests');
  String get eventGroupReject => _get('event_group_reject');
  String get eventGroupApprove => _get('event_group_approve');
  String eventGroupFailedLoadMembers(Object error) =>
      _fmt('event_group_failed_load_members', {'error': error});
  String get eventGroupNoMembersYet => _get('event_group_no_members_yet');
  String get eventGroupMemberFallback => _get('event_group_member_fallback');
  String get eventGroupAdminBadge => _get('event_group_admin_badge');
  String eventGroupRemoveMemberTitle(Object name) =>
      _fmt('event_group_remove_member_title', {'name': name});
  String get eventGroupRemoveMemberBody =>
      _get('event_group_remove_member_body');
  String get eventGroupRemove => _get('event_group_remove');
  String get eventGroupAddUserToGroup =>
      _get('event_group_add_user_to_group');
  String get eventGroupNotFollowingAnyone =>
      _get('event_group_not_following_anyone');
  String eventGroupAddedToGroup(Object name) =>
      _fmt('event_group_added_to_group', {'name': name});
  String get eventGroupAdd => _get('event_group_add');
  String get eventNotifTitle => _get('event_notif_title');
  String get eventNotifSaved => _get('event_notif_saved');
  String eventNotifCouldNotSave(Object error) =>
      _fmt('event_notif_could_not_save', {'error': error});
  String get eventNotifNewEventNotifications =>
      _get('event_notif_new_event_notifications');
  String get eventNotifNewEventSubtitle =>
      _get('event_notif_new_event_subtitle');
  String get eventNotifEventTypes => _get('event_notif_event_types');
  String get eventNotifAllTypesDesc => _get('event_notif_all_types_desc');
  String get eventNotifCustomTypesDesc =>
      _get('event_notif_custom_types_desc');
  String get eventNotifAllTypes => _get('event_notif_all_types');
  String get eventNotifCountries => _get('event_notif_countries');
  String get eventNotifAllCountriesDesc =>
      _get('event_notif_all_countries_desc');
  String get eventNotifCustomCountriesDesc =>
      _get('event_notif_custom_countries_desc');
  String get eventNotifAllCountries => _get('event_notif_all_countries');
  String get groupSettingsDeleteGroupTitle =>
      _get('group_settings_delete_group_title');
  String groupSettingsDeleteGroupBody(Object name) =>
      _fmt('group_settings_delete_group_body', {'name': name});
  String groupSettingsFailedToDelete(Object error) =>
      _fmt('group_settings_failed_to_delete', {'error': error});
  String get groupSettingsSaved => _get('group_settings_saved');
  String groupSettingsError(Object error) =>
      _fmt('group_settings_error', {'error': error});
  String get groupSettingsLeaveGroupTitle =>
      _get('group_settings_leave_group_title');
  String groupSettingsLeaveGroupBody(Object name) =>
      _fmt('group_settings_leave_group_body', {'name': name});
  String groupSettingsFailedToLeave(Object error) =>
      _fmt('group_settings_failed_to_leave', {'error': error});
  String get groupSettingsGroupNotFound =>
      _get('group_settings_group_not_found');
  String get groupSettingsLeaveGroup => _get('group_settings_leave_group');
  String get groupSettingsDeleteGroup => _get('group_settings_delete_group');
  String get groupSettingsMember => _get('group_settings_member');
  String get groupSettingsMembers => _get('group_settings_members');
  String get groupSettingsUserFallback =>
      _get('group_settings_user_fallback');
  String get groupSettingsYouSuffix => _get('group_settings_you_suffix');
  String get groupSettingsAdmin => _get('group_settings_admin');
  String get groupSettingsMessagingPermissions =>
      _get('group_settings_messaging_permissions');
  String get groupSettingsRestrictMessaging =>
      _get('group_settings_restrict_messaging');
  String get groupSettingsRestrictMessagingDesc =>
      _get('group_settings_restrict_messaging_desc');
  String get groupSettingsAdminOnlyMode =>
      _get('group_settings_admin_only_mode');
  String get groupSettingsAdminOnlyModeDesc =>
      _get('group_settings_admin_only_mode_desc');
  String get groupSettingsEnableMediaSharing =>
      _get('group_settings_enable_media_sharing');
  String get groupSettingsEnableMediaSharingDesc =>
      _get('group_settings_enable_media_sharing_desc');
  String get groupSettingsSaveSettings =>
      _get('group_settings_save_settings');
  String eventDetailDeadline(Object date) =>
      _fmt('event_detail_deadline', {'date': date});
  String get eventDetailApplyBelow => _get('event_detail_apply_below');
  String get eventDetailRegisterBelow => _get('event_detail_register_below');
  String get eventDetailContact => _get('event_detail_contact');
  String get eventDetailCouldNotOpenLink =>
      _get('event_detail_could_not_open_link');
  String get eventDetailApply => _get('event_detail_apply');
  String get eventDetailRegistration => _get('event_detail_registration');
  String get eventDetailRequestPending =>
      _get('event_detail_request_pending');
  String get eventDetailApproved => _get('event_detail_approved');
  String get eventDetailRejectedRetry => _get('event_detail_rejected_retry');
  String get eventRegRequestSubmitted =>
      _get('event_reg_request_submitted');
  String eventRegFailed(Object error) =>
      _fmt('event_reg_failed', {'error': error});
  String get eventRegRegisterFor => _get('event_reg_register_for');
  String get eventRegFullName => _get('event_reg_full_name');
  String get eventRegNameHint => _get('event_reg_name_hint');
  String get eventRegRequired => _get('event_reg_required');
  String get eventRegEmail => _get('event_reg_email');
  String get eventRegEmailHint => _get('event_reg_email_hint');
  String get eventRegInvalidEmail => _get('event_reg_invalid_email');
  String get eventRegPhone => _get('event_reg_phone');
  String get eventRegPhoneHint => _get('event_reg_phone_hint');
  String get eventRegTooShort => _get('event_reg_too_short');
  String get eventRegSubmitRequest => _get('event_reg_submit_request');
  String get eventUnavailableTitle => _get('event_unavailable_title');
  String get eventUnavailableBody => _get('event_unavailable_body');
  String get eventUnavailableGoBack => _get('event_unavailable_go_back');
  String createGroupFailed(Object error) =>
      _fmt('create_group_failed', {'error': error});
  String get createGroupNewGroup => _get('create_group_new_group');
  String get createGroupGroupName => _get('create_group_group_name');
  String get createGroupSearchPeople => _get('create_group_search_people');
  String get createGroupAddMembers => _get('create_group_add_members');
  String get createGroupNotFollowingAnyone =>
      _get('create_group_not_following_anyone');
  String createGroupError(Object error) =>
      _fmt('create_group_error', {'error': error});
  String get createGroupCreate => _get('create_group_create');
  String createGroupCreateCount(Object count) =>
      _fmt('create_group_create_count', {'count': count});
  String get locationMapCouldNotOpen => _get('location_map_could_not_open');
  String get locationMapLocation => _get('location_map_location');
  String get locationMapOpenInMaps => _get('location_map_open_in_maps');
  String get eventsFilterAll => _get('events_filter_all');
  String get eventsFilterNearby => _get('events_filter_nearby');
  String get eventsFilterCity => _get('events_filter_city');

  // ── ADMIN SCREENS (added) ──
  String get adminNoAccess => _get('admin_no_access');
  String get adminDashboardTitle => _get('admin_dashboard_title');
  String get adminTileUsersTitle => _get('admin_tile_users_title');
  String get adminTileUsersSubtitle => _get('admin_tile_users_subtitle');
  String get adminTilePostsTitle => _get('admin_tile_posts_title');
  String get adminTilePostsSubtitle => _get('admin_tile_posts_subtitle');
  String get adminTileReportsSubtitle => _get('admin_tile_reports_subtitle');
  String get adminTileContactSubtitle => _get('admin_tile_contact_subtitle');
  String get adminTileEventsSubtitle => _get('admin_tile_events_subtitle');
  String get adminBlacklistedEmails => _get('admin_blacklisted_emails');
  String get adminTileBlacklistSubtitle =>
      _get('admin_tile_blacklist_subtitle');
  String get adminAppSettings => _get('admin_app_settings');
  String get adminTileSettingsSubtitle =>
      _get('admin_tile_settings_subtitle');
  String get adminUsersSearchHint => _get('admin_users_search_hint');
  String get adminNoUsersMatch => _get('admin_no_users_match');
  String get adminBadge => _get('admin_badge');
  String get adminSuspendedBadge => _get('admin_suspended_badge');
  String get adminDemoteToUser => _get('admin_demote_to_user');
  String get adminPromoteToAdmin => _get('admin_promote_to_admin');
  String get adminSuspend => _get('admin_suspend');
  String get adminUnsuspend => _get('admin_unsuspend');
  String get adminDeleteUser => _get('admin_delete_user');
  String get adminDeleteUserPermanentlyTitle =>
      _get('admin_delete_user_permanently_title');
  String get adminDeleteUserPermanentlyBody =>
      _get('admin_delete_user_permanently_body');
  String get adminDeleteEverything => _get('admin_delete_everything');
  String get adminDeletingAllUserData => _get('admin_deleting_all_user_data');
  String get adminUserDeletedBlacklisted =>
      _get('admin_user_deleted_blacklisted');
  String adminPostByAuthor(Object author) =>
      _fmt('admin_post_by_author', {'author': author});
  String get adminUnknown => _get('admin_unknown');
  String get adminNewEvent => _get('admin_new_event');
  String get adminEditEvent => _get('admin_edit_event');
  String get adminNoEventsYet => _get('admin_no_events_yet');
  String get adminDeleteEventTitle => _get('admin_delete_event_title');
  String get adminDeleteEventBody => _get('admin_delete_event_body');
  String adminUploadFailed(Object error) =>
      _fmt('admin_upload_failed', {'error': error});
  String get adminSelectDeadline => _get('admin_select_deadline');
  String get adminTitleRequired => _get('admin_title_required');
  String get adminPickEventType => _get('admin_pick_event_type');
  String get adminCountryRequired => _get('admin_country_required');
  String get adminDescriptionRequired => _get('admin_description_required');
  String get adminAddAtLeastOneImage => _get('admin_add_at_least_one_image');
  String get adminFixHighlightedFields =>
      _get('admin_fix_highlighted_fields');
  String adminSaveFailed(Object error) =>
      _fmt('admin_save_failed', {'error': error});
  String get adminFieldTitle => _get('admin_field_title');
  String get adminEnterEventTitle => _get('admin_enter_event_title');
  String get adminFieldSubtitle => _get('admin_field_subtitle');
  String get adminShortSubtitleOptional =>
      _get('admin_short_subtitle_optional');
  String get adminFieldEventType => _get('admin_field_event_type');
  String get adminChooseEventType => _get('admin_choose_event_type');
  String get adminSearchEventType => _get('admin_search_event_type');
  String get adminFieldCountry => _get('admin_field_country');
  String get adminChooseCountry => _get('admin_choose_country');
  String get adminSearchCountry => _get('admin_search_country');
  String get adminFieldDescription => _get('admin_field_description');
  String get adminDescribeTheEvent => _get('admin_describe_the_event');
  String get adminFieldLink => _get('admin_field_link');
  String get adminRegistrationOrInfoLink =>
      _get('admin_registration_or_info_link');
  String get adminFieldPhone => _get('admin_field_phone');
  String get adminContactPhoneOptional =>
      _get('admin_contact_phone_optional');
  String get adminFieldEmail => _get('admin_field_email');
  String get adminContactEmailOptional =>
      _get('admin_contact_email_optional');
  String get adminFieldImages => _get('admin_field_images');
  String adminFieldIsRequired(Object label) =>
      _fmt('admin_field_is_required', {'label': label});
  String get adminFieldDeadline => _get('admin_field_deadline');
  String get adminClearDeadline => _get('admin_clear_deadline');
  String get adminNoResults => _get('admin_no_results');
  String get adminPostReports => _get('admin_post_reports');
  String get adminPostReportsSubtitle => _get('admin_post_reports_subtitle');
  String get adminDiscussReports => _get('admin_discuss_reports');
  String get adminDiscussReportsSubtitle =>
      _get('admin_discuss_reports_subtitle');
  String get adminProfileReports => _get('admin_profile_reports');
  String get adminProfileReportsSubtitle =>
      _get('admin_profile_reports_subtitle');
  String get adminErrorReportsSubtitle =>
      _get('admin_error_reports_subtitle');
  String get adminClearResolvedTitle => _get('admin_clear_resolved_title');
  String adminClearResolvedBody(Object count) =>
      _fmt('admin_clear_resolved_body', {'count': count});
  String get adminResolvedReportsCleared =>
      _get('admin_resolved_reports_cleared');
  String get adminClearResolved => _get('admin_clear_resolved');
  String adminTabOpen(Object count) =>
      _fmt('admin_tab_open', {'count': count});
  String adminTabResolved(Object count) =>
      _fmt('admin_tab_resolved', {'count': count});
  String get adminNoPostReports => _get('admin_no_post_reports');
  String get adminNoDiscussReports => _get('admin_no_discuss_reports');
  String get adminNoProfileReports => _get('admin_no_profile_reports');
  String get adminNoOpenReports => _get('admin_no_open_reports');
  String get adminFreshReportsHere => _get('admin_fresh_reports_here');
  String get adminNothingResolvedYet => _get('admin_nothing_resolved_yet');
  String get adminClosedReportsMoveHere =>
      _get('admin_closed_reports_move_here');
  String get adminNoCaption => _get('admin_no_caption');
  String get adminNoQuestionText => _get('admin_no_question_text');
  String get adminReportedPost => _get('admin_reported_post');
  String get adminReportedThread => _get('admin_reported_thread');
  String get adminReportedProfile => _get('admin_reported_profile');
  String get adminPostAuthor => _get('admin_post_author');
  String get adminThreadAuthor => _get('admin_thread_author');
  String get adminReporter => _get('admin_reporter');
  String get adminReason => _get('admin_reason');
  String get adminWhen => _get('admin_when');
  String get adminDetails => _get('admin_details');
  String get adminReopen => _get('admin_reopen');
  String get adminMarkResolved => _get('admin_mark_resolved');
  String get adminViewPost => _get('admin_view_post');
  String get adminViewThread => _get('admin_view_thread');
  String get adminViewProfile => _get('admin_view_profile');
  String get adminDeleteReportTitle => _get('admin_delete_report_title');
  String get adminDeleteReportBody => _get('admin_delete_report_body');
  String get adminTakeDownPostTitle => _get('admin_take_down_post_title');
  String get adminTakeDownPostBody => _get('admin_take_down_post_body');
  String get adminTakeDownThreadTitle => _get('admin_take_down_thread_title');
  String get adminTakeDownThreadBody => _get('admin_take_down_thread_body');
  String get adminDeleteReport => _get('admin_delete_report');
  String get adminTakeDownPost => _get('admin_take_down_post');
  String get adminTakeDownThread => _get('admin_take_down_thread');
  String get adminReportDeleted => _get('admin_report_deleted');
  String get adminPostTakenDown => _get('admin_post_taken_down');
  String get adminThreadTakenDown => _get('admin_thread_taken_down');
  String adminActionFailed(Object error) =>
      _fmt('admin_action_failed', {'error': error});
  String get adminRemoveUserTitle => _get('admin_remove_user_title');
  String get adminRemoveUserBody => _get('admin_remove_user_body');
  String get adminRemoveUser => _get('admin_remove_user');
  String get adminUserRemoved => _get('admin_user_removed');
  String adminClearedSolvedReports(Object count) =>
      _fmt('admin_cleared_solved_reports', {'count': count});
  String get adminClearAllSolvedReports =>
      _get('admin_clear_all_solved_reports');
  String adminTabUnsolved(Object count) =>
      _fmt('admin_tab_unsolved', {'count': count});
  String adminTabSolved(Object count) =>
      _fmt('admin_tab_solved', {'count': count});
  String get adminNoErrorReports => _get('admin_no_error_reports');
  String get adminNoUnsolvedErrors => _get('admin_no_unsolved_errors');
  String get adminCapturedErrorsHere => _get('admin_captured_errors_here');
  String get adminNothingSolvedYet => _get('admin_nothing_solved_yet');
  String get adminSolvedReportsMoveHere =>
      _get('admin_solved_reports_move_here');
  String get adminMostFrequent => _get('admin_most_frequent');
  String get adminUnknownScreen => _get('admin_unknown_screen');
  String get adminPageScreen => _get('admin_page_screen');
  String get adminType => _get('admin_type');
  String get adminPlatform => _get('admin_platform');
  String get adminAppVersionLabel => _get('admin_app_version_label');
  String get adminNotSignedIn => _get('admin_not_signed_in');
  String get adminContext => _get('admin_context');
  String get adminErrorMessage => _get('admin_error_message');
  String get adminStackTrace => _get('admin_stack_trace');
  String get adminNoStack => _get('admin_no_stack');
  String get adminCopiedToClipboard => _get('admin_copied_to_clipboard');
  String get adminNoBlacklistedEmails => _get('admin_no_blacklisted_emails');
  String adminDeletedOn(Object date) =>
      _fmt('admin_deleted_on', {'date': date});
  String get adminRemoveFromBlacklistTitle =>
      _get('admin_remove_from_blacklist_title');
  String adminAllowToRegisterAgain(Object email) =>
      _fmt('admin_allow_to_register_again', {'email': email});
  String get adminRemoveFromBlacklistTooltip =>
      _get('admin_remove_from_blacklist_tooltip');
  String adminCouldNotLoad(Object error) =>
      _fmt('admin_could_not_load', {'error': error});
  String get adminNoRequests => _get('admin_no_requests');
  String get adminFilterAll => _get('admin_filter_all');
  String get adminFilterMessages => _get('admin_filter_messages');
  String get adminFilterOrganization => _get('admin_filter_organization');
  String get adminFilterAwaitingReply => _get('admin_filter_awaiting_reply');
  String get adminBadgeOrganization => _get('admin_badge_organization');
  String get adminBadgeMessage => _get('admin_badge_message');
  String get adminStatusOpen => _get('admin_status_open');
  String get adminStatusAnswered => _get('admin_status_answered');
  String get adminStatusApproved => _get('admin_status_approved');
  String get adminSaved => _get('admin_saved');
  String get adminSectionFeatureFlags => _get('admin_section_feature_flags');
  String get adminFlagStories => _get('admin_flag_stories');
  String get adminFlagReposts => _get('admin_flag_reposts');
  String get adminFlagTranslate => _get('admin_flag_translate');
  String get adminSectionAnnouncement => _get('admin_section_announcement');
  String get adminAnnouncementHint => _get('admin_announcement_hint');
  String get adminSectionMaintenance => _get('admin_section_maintenance');
  String get adminFlagMaintenance => _get('admin_flag_maintenance');
  String get adminSectionMinAppVersion =>
      _get('admin_section_min_app_version');
  String get adminMinVersionHint => _get('admin_min_version_hint');
  String get adminSectionContactEmail => _get('admin_section_contact_email');
  String get adminContactEmailHint => _get('admin_contact_email_hint');
  String get adminSectionAppStoreLinks =>
      _get('admin_section_app_store_links');
  String get adminAppStoreLinksDesc => _get('admin_app_store_links_desc');
  String get adminIosUrlHint => _get('admin_ios_url_hint');
  String get adminAndroidUrlHint => _get('admin_android_url_hint');
  String get adminSectionEventTypes => _get('admin_section_event_types');
  String get adminEventTypesDesc => _get('admin_event_types_desc');
  String get adminAddEventType => _get('admin_add_event_type');
  String get adminSectionEventCountries =>
      _get('admin_section_event_countries');
  String get adminEventCountriesDesc => _get('admin_event_countries_desc');
  String get adminAddCountry => _get('admin_add_country');

  // ── PROFILE SCREENS (added) ──
  String get profileNoUsersYet => _get('profile_no_users_yet');
  String get profileNoProfileData => _get('profile_no_profile_data');
  String get profileOnlyFollowersCanSee =>
      _get('profile_only_followers_can_see');
  String get profileAnyoneCanSee => _get('profile_anyone_can_see');
  String get profileAdminPanel => _get('profile_admin_panel');
  String get profileDeleteAccountSubtitle =>
      _get('profile_delete_account_subtitle');
  String get profileNoBlockedUsers => _get('profile_no_blocked_users');
  String get profileBlockedUsersHint => _get('profile_blocked_users_hint');
  String get profileDeleteAccountTitle =>
      _get('profile_delete_account_title');
  String get profileDeleteAccountBody => _get('profile_delete_account_body');
  String get profileDeleteEverything => _get('profile_delete_everything');
  String get profileDeletingAccount => _get('profile_deleting_account');
  String get profileReauthRequired => _get('profile_reauth_required');
  String get profileNoRepostsYet => _get('profile_no_reposts_yet');
  String get profileNoRepostsSubtitle => _get('profile_no_reposts_subtitle');
  String get profileNoSavedPosts => _get('profile_no_saved_posts');
  String get profileNoSavedSubtitle => _get('profile_no_saved_subtitle');
  String get profileNoQuestionsAsked => _get('profile_no_questions_asked');
  String get profileNoAnswersYet => _get('profile_no_answers_yet');
  String get profileNoQuestionsAskedSubtitle =>
      _get('profile_no_questions_asked_subtitle');
  String get profileNoAnswersSubtitle =>
      _get('profile_no_answers_subtitle');
  String get profileQuestionsAsked => _get('profile_questions_asked');
  String get profileQuestionsAnswered => _get('profile_questions_answered');
  String get profileInviteFriends => _get('profile_invite_friends');
  String get profileCreateFirstPost => _get('profile_create_first_post');
  String get profileShareYourContent => _get('profile_share_your_content');
  String get profileCreate => _get('profile_create');
  String profileVisitorsCount(Object count) =>
      _fmt('profile_visitors_count', {'count': count});
  String get profileNoVisitsYet => _get('profile_no_visits_yet');
  String get profileNoVisitsSubtitle => _get('profile_no_visits_subtitle');
  String profileVisited(Object time) =>
      _fmt('profile_visited', {'time': time});
  String profileVisitedTimes(Object time, Object count) =>
      _fmt('profile_visited_times', {'time': time, 'count': count});
  String profileVisitorVisits(Object name, Object count) =>
      _fmt('profile_visitor_visits', {'name': name, 'count': count});
  String userFollowActionFailed(Object error) =>
      _fmt('user_follow_action_failed', {'error': error});
  String get userReportProfile => _get('user_report_profile');
  String get userReportReasonSpam => _get('user_report_reason_spam');
  String get userReportReasonImpersonation =>
      _get('user_report_reason_impersonation');
  String get userReportReasonHarassment =>
      _get('user_report_reason_harassment');
  String get userReportReasonHateSpeech =>
      _get('user_report_reason_hate_speech');
  String get userReportReasonNudity => _get('user_report_reason_nudity');
  String get userReportReasonViolence =>
      _get('user_report_reason_violence');
  String get userReportReasonOther => _get('user_report_reason_other');
  String get userReportDetailsOptional =>
      _get('user_report_details_optional');
  String get userNotFound => _get('user_not_found');
  String get userUnblocked => _get('user_unblocked');
  String get userBlocked => _get('user_blocked');
  String userFailedBlockUnblock(Object error) =>
      _fmt('user_failed_block_unblock', {'error': error});
  String get userYouBlockedThisUser => _get('user_you_blocked_this_user');
  String get userBlockedContentHidden =>
      _get('user_blocked_content_hidden');
  String userFailedUnblock(Object error) =>
      _fmt('user_failed_unblock', {'error': error});
  String get userPrivateFollowPrompt => _get('user_private_follow_prompt');
  String editProfileUploadFailed(Object error) =>
      _fmt('edit_profile_upload_failed', {'error': error});
  String editProfileCoverUploadFailed(Object error) =>
      _fmt('edit_profile_cover_upload_failed', {'error': error});
  String get editProfileUsernameEmpty => _get('edit_profile_username_empty');
  String get editProfileUsernameInvalid =>
      _get('edit_profile_username_invalid');
  String get editProfileUsernameTaken => _get('edit_profile_username_taken');
  String get editProfileUpdated => _get('edit_profile_updated');
  String editProfileCouldNotSave(Object error) =>
      _fmt('edit_profile_could_not_save', {'error': error});
  String get editProfileChangePhoto => _get('edit_profile_change_photo');
  String get editProfileChangeCover => _get('edit_profile_change_cover');
  String get editProfileName => _get('edit_profile_name');
  String get editProfileNameHint => _get('edit_profile_name_hint');
  String get editProfileUsernameHint => _get('edit_profile_username_hint');
  String get editProfileBioHint => _get('edit_profile_bio_hint');
  String get editProfileSelectGender => _get('edit_profile_select_gender');
  String get editProfilePreferNotToSay =>
      _get('edit_profile_prefer_not_to_say');
  String get editProfileInterestsGoals =>
      _get('edit_profile_interests_goals');
  String get editProfileInterestsDesc => _get('edit_profile_interests_desc');
  String get requestHiddenRequests => _get('request_hidden_requests');
  String get requestHiddenRequestsSubtitle =>
      _get('request_hidden_requests_subtitle');
  String get aboutEditorIAmA => _get('about_editor_i_am_a');
  String get aboutEditorField => _get('about_editor_field');
  String get aboutEditorAcademicLevel => _get('about_editor_academic_level');
  String get aboutEditorMyGoals => _get('about_editor_my_goals');
  String get aboutOptionStudent => _get('about_option_student');
  String get aboutOptionResearcher => _get('about_option_researcher');
  String get aboutOptionProfessor => _get('about_option_professor');
  String get aboutOptionTraveler => _get('about_option_traveler');
  String get aboutOptionTech => _get('about_option_tech');
  String get aboutOptionMedicine => _get('about_option_medicine');
  String get aboutOptionLaw => _get('about_option_law');
  String get aboutOptionBusiness => _get('about_option_business');
  String get aboutOptionArts => _get('about_option_arts');
  String get aboutOptionEngineering => _get('about_option_engineering');
  String get aboutOptionScience => _get('about_option_science');
  String get aboutOptionEducation => _get('about_option_education');
  String get aboutOptionSocialSciences =>
      _get('about_option_social_sciences');
  String get aboutOptionOther => _get('about_option_other');
  String get aboutOptionUndergraduate =>
      _get('about_option_undergraduate');
  String get aboutOptionMasters => _get('about_option_masters');
  String get aboutOptionPhd => _get('about_option_phd');
  String get aboutOptionFaculty => _get('about_option_faculty');
  String get aboutOptionInternships => _get('about_option_internships');
  String get aboutOptionScholarships => _get('about_option_scholarships');
  String get aboutOptionConferences => _get('about_option_conferences');
  String get aboutOptionResearch => _get('about_option_research');
  String get aboutOptionNetworking => _get('about_option_networking');
  String get aboutOptionLocalEvents => _get('about_option_local_events');

  // ──────────────────────────────────────────────────────────────
  // Relative time
  //
  // Shared, localized "x minutes ago" formatter. Use this everywhere
  // instead of per-screen helpers so all timestamps read consistently
  // in every language.
  // ──────────────────────────────────────────────────────────────

  /// Wraps [text] in a Unicode directional isolate matching the
  /// current language, so the run renders as one self-contained
  /// unit even when concatenated next to text of the other
  /// direction (e.g. a Latin username + an RTL time string).
  ///
  /// This is needed because some RTL strings — notably the Kurdish
  /// "{n} ڕۆژ پێش ئێستا" — *start* with a digit (a bidi-weak
  /// character). Without an isolate, the leading digit attaches to
  /// the neighbouring run and the phrase visually splits. Arabic
  /// strings start with the word "قبل" (bidi-strong) so they don't
  /// hit this, which is why the bug only showed in Kurdish.
  ///
  /// U+2067 = RIGHT-TO-LEFT ISOLATE, U+2066 = LEFT-TO-RIGHT ISOLATE,
  /// U+2069 = POP DIRECTIONAL ISOLATE. These are zero-width. Written
  /// as \u escapes so the source stays free of invisible characters.
  String isolate(String text) {
    const pop = '\u2069';
    final open = language.isRtl ? '\u2067' : '\u2066';
    return '$open$text$pop';
  }

  /// "just now" / "5m ago" / "3d ago" … for [time]. A null [time]
  /// is treated as the current moment ("just now").
  ///
  /// The result is wrapped in a directional isolate so it can be
  /// safely concatenated next to text of the opposite direction.
  String timeAgo(DateTime? time) {
    return isolate(_timeAgoRaw(time));
  }

  String _timeAgoRaw(DateTime? time) {
    if (time == null) return _get('time_just_now');
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return _get('time_just_now');
    if (diff.inMinutes < 60) {
      return _fmt('time_minutes_ago', {'n': diff.inMinutes});
    }
    if (diff.inHours < 24) {
      return _fmt('time_hours_ago', {'n': diff.inHours});
    }
    if (diff.inDays < 7) {
      return _fmt('time_days_ago', {'n': diff.inDays});
    }
    if (diff.inDays < 30) {
      return _fmt('time_weeks_ago', {'n': (diff.inDays / 7).floor()});
    }
    if (diff.inDays < 365) {
      return _fmt('time_months_ago', {'n': (diff.inDays / 30).floor()});
    }
    return _fmt('time_years_ago', {'n': (diff.inDays / 365).floor()});
  }

  /// "last seen just now" / "last seen 5m ago" … for a presence
  /// timestamp. Wrapped in a directional isolate (see [isolate]).
  String lastSeenLabel(DateTime time) {
    return isolate(_lastSeenRaw(time));
  }

  String _lastSeenRaw(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return _get('time_last_seen_just_now');
    if (diff.inMinutes < 60) {
      return _fmt('time_last_seen_minutes_ago', {'n': diff.inMinutes});
    }
    if (diff.inHours < 24) {
      return _fmt('time_last_seen_hours_ago', {'n': diff.inHours});
    }
    return _fmt('time_last_seen_days_ago', {'n': diff.inDays});
  }

  // ── VERSION GATE (added) ──
  String get updateRequiredTitle => _get('update_required_title');
  String updateRequiredBody(Object required, Object current) => _fmt(
        'update_required_body',
        {'required': required, 'current': current},
      );

  // ── SETTINGS SCREEN (added) ──
  String get settingsSectionNotifications =>
      _get('settings_section_notifications');
  String get settingsSectionInvite => _get('settings_section_invite');
  String get settingsSectionSupport => _get('settings_section_support');
  String get settingsSectionOrganization =>
      _get('settings_section_organization');
  String get settingsSetPasswordSubtitle =>
      _get('settings_set_password_subtitle');
  String get settingsVisitorsSeeWho => _get('settings_visitors_see_who');
  String get settingsVisitorsViewedOne =>
      _get('settings_visitors_viewed_one');
  String settingsVisitorsViewedMany(Object count) =>
      _fmt('settings_visitors_viewed_many', {'count': count});
  String get settingsEventNotifSubtitle =>
      _get('settings_event_notif_subtitle');
  String get settingsAppLanguageSubtitle =>
      _get('settings_app_language_subtitle');
  String get settingsTranslationLanguageSubtitle =>
      _get('settings_translation_language_subtitle');
  String get settingsInviteFriends => _get('settings_invite_friends');
  String get settingsInviteFriendsSubtitle =>
      _get('settings_invite_friends_subtitle');
  String get settingsContactUsSubtitle =>
      _get('settings_contact_us_subtitle');
  String get settingsManageEventsSubtitle =>
      _get('settings_manage_events_subtitle');
  String get settingsAdminPanel => _get('settings_admin_panel');
  String get settingsPreferredLanguage =>
      _get('settings_preferred_language');
  String get settingsBlockedUsersTitle =>
      _get('settings_blocked_users_title');
  String get settingsBlockedUsersHint => _get('settings_blocked_users_hint');
  String get settingsCannotChangeEmailTitle =>
      _get('settings_cannot_change_email_title');
  String get settingsCannotChangeEmailBody =>
      _get('settings_cannot_change_email_body');
  String get settingsVerificationEmailSent =>
      _get('settings_verification_email_sent');
  String get settingsSetPasswordDialogBody =>
      _get('settings_set_password_dialog_body');
  String get settingsNewPassword => _get('settings_new_password');
  String get settingsConfirmPassword => _get('settings_confirm_password');
  String get settingsAllFieldsRequired =>
      _get('settings_all_fields_required');
  String get settingsPasswordMin6 => _get('settings_password_min_6');
  String get settingsPasswordsDoNotMatch =>
      _get('settings_passwords_do_not_match');
  String get settingsPasswordSetSuccess =>
      _get('settings_password_set_success');
  String get settingsSetPasswordButton =>
      _get('settings_set_password_button');
  String get settingsPasswordTooWeak => _get('settings_password_too_weak');
  String get settingsPasswordAlreadyLinked =>
      _get('settings_password_already_linked');
  String get settingsSomethingWentWrong =>
      _get('settings_something_went_wrong');
  String get settingsSomethingWentWrongRetry =>
      _get('settings_something_went_wrong_retry');
  String get settingsPasswordUpdated => _get('settings_password_updated');
  String get settingsSecurityRelogin => _get('settings_security_relogin');
  String settingsDeleteFailed(Object error) =>
      _fmt('settings_delete_failed', {'error': error});
  String get settingsNewEmail => _get('settings_new_email');
  String get settingsCurrentPassword => _get('settings_current_password');
  String get settingsNoEmailAccount => _get('settings_no_email_account');
  String get settingsEmailMustDiffer => _get('settings_email_must_differ');
  String get settingsIncorrectPassword =>
      _get('settings_incorrect_password');
  String get settingsSecurityReloginShort =>
      _get('settings_security_relogin_short');
  String get settingsEmailAlreadyInUse =>
      _get('settings_email_already_in_use');
  String get settingsEmailInvalid => _get('settings_email_invalid');
  String get settingsTooManyRequests => _get('settings_too_many_requests');
  String get settingsNetworkError => _get('settings_network_error');
  String get settingsEmailChangeNotEnabled =>
      _get('settings_email_change_not_enabled');
  String get settingsConfirmNewPassword =>
      _get('settings_confirm_new_password');
  String get settingsIncorrectCurrentPassword =>
      _get('settings_incorrect_current_password');
  String get settingsNewPasswordTooWeak =>
      _get('settings_new_password_too_weak');
  String settingsResetEmailSent(Object email) =>
      _fmt('settings_reset_email_sent', {'email': email});
  String get settingsEmailInvalidYours =>
      _get('settings_email_invalid_yours');
  String get settingsCouldNotSendReset =>
      _get('settings_could_not_send_reset');

  // ── MERGE WITH DEMO (added) ──
  String get adminStatusRevoked => _get('admin_status_revoked');
  String get adminPickFundingStatus => _get('admin_pick_funding_status');
  String get adminSearchByUsernameOrCaption =>
      _get('admin_search_by_username_or_caption');
  String get adminNoPostsMatch => _get('admin_no_posts_match');
  String get createPostBlockedTitle => _get('create_post_blocked_title');
  String get createPostBlockedBody => _get('create_post_blocked_body');
  String get eventsNoOneInField => _get('events_no_one_in_field');
  String get eventsNoOneAtAcademicLevel =>
      _get('events_no_one_at_academic_level');
  String get eventsFilterField => _get('events_filter_field');
  String get eventsFilterLevel => _get('events_filter_level');
  String get eventsNoMatchingPeople => _get('events_no_matching_people');
  String eventsNoTypeEvents(Object type) =>
      _fmt('events_no_type_events', {'type': type});
  String eventsNoTypeEventsInCity(Object type, Object city) =>
      _fmt('events_no_type_events_in_city', {'type': type, 'city': city});
  String get clearSearch => _get('clear_search');

  // Shared city picker.
  String get cityPickerSearchHint => _get('city_picker_search_hint');
  String get cityPickerNoResults => _get('city_picker_no_results');
  String get cityPickerSelect => _get('city_picker_select');
  String get cityPickerLoading => _get('city_picker_loading');
  String get cityPickerAll => _get('city_picker_all');
}

/// Convenience accessor: `context.t.settings`.
///
/// This relies on the active locale being applied via `MaterialApp`'s
/// `locale`; the [Localizations] widget rebuilds dependents when it
/// changes, so reading [Localizations.localeOf] here makes any widget
/// that uses `context.t` rebuild on a language switch.
extension AppStringsX on BuildContext {
  AppStrings get t {
    final code = Localizations.localeOf(this).languageCode;
    return AppStrings(AppLanguage.fromCode(code));
  }
}
