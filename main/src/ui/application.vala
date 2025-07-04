using Gtk;

using Dino.Entities;
using Dino.Ui;
using Xmpp;

public class Dino.Ui.Application : Adw.Application, Dino.Application {
    private const string[] KEY_COMBINATION_QUIT = {"<Ctrl>Q", null};
    private const string[] KEY_COMBINATION_ADD_CHAT = {"<Ctrl>T", null};
    private const string[] KEY_COMBINATION_ADD_CONFERENCE = {"<Ctrl>G", null};
    private const string[] KEY_COMBINATION_LOOP_CONVERSATIONS = {"<Ctrl>Tab", null};
    private const string[] KEY_COMBINATION_LOOP_CONVERSATIONS_REV = {"<Ctrl><Shift>Tab", null};
    private const string[] KEY_COMBINATION_SHOW_SETTINGS = {"<Ctrl>comma", null};

    public MainWindow window;
    public MainWindowController controller;

    public Database db { get; set; }
    public Dino.Entities.Settings settings { get; set; }
    private Config config { get; set; }
    public StreamInteractor stream_interactor { get; set; }
    public Plugins.Registry plugin_registry { get; set; default = new Plugins.Registry(); }
    public SearchPathGenerator? search_path_generator { get; set; }

    internal static bool print_version = false;
    private const OptionEntry[] options = {
        { "version", 0, 0, OptionArg.NONE, ref print_version, "Display version number", null },
        { null }
    };

    public Application() throws Error {
        Object(application_id: "im.dino.Dino", flags: ApplicationFlags.HANDLES_OPEN);
        init();
        Environment.set_application_name("Dino");
        Window.set_default_icon_name("im.dino.Dino");

        create_actions();
        add_main_option_entries(options);

        startup.connect(() => {
            if (print_version) {
                print(@"Dino $(Dino.get_version())\n");
                Process.exit(0);
            }

            NotificationEvents notification_events = stream_interactor.get_module(NotificationEvents.IDENTITY);
            get_notifications_dbus.begin((_, res) => {
                // It might take a bit to get the interface. NotificationEvents will queue any notifications in the meantime.
                try {
                    DBusNotifications? dbus_notifications = get_notifications_dbus.end(res);
                    if (dbus_notifications != null) {
                        FreeDesktopNotifier free_desktop_notifier = new FreeDesktopNotifier(stream_interactor, dbus_notifications);
                        notification_events.register_notification_provider.begin(free_desktop_notifier);
                    } else {
                        notification_events.register_notification_provider.begin(new GNotificationsNotifier(stream_interactor));
                    }
                } catch (Error e) {
                    debug("Failed accessing fdo notification server: %s", e.message);
                }
            });

            notification_events.notify_content_item.connect((content_item, conversation) => {
                // Set urgency hint also if (normal) notifications are disabled
                // Don't set urgency hint in GNOME, produces "Window is active" notification
                var desktop_env = Environment.get_variable("XDG_CURRENT_DESKTOP");
                if (desktop_env == null || !desktop_env.down().contains("gnome")) {
                    if (this.active_window != null) {
//                        this.active_window.urgency_hint = true;
                    }
                }
            });
            stream_interactor.get_module(FileManager.IDENTITY).add_metadata_provider(new Util.AudioVideoFileMetadataProvider());
        });

        activate.connect(() => {
            if (window == null) {
                controller = new MainWindowController(this, stream_interactor, db);
                config = new Config(db);
                window = new MainWindow(this, stream_interactor, db, config);
                controller.set_window(window);
                if ((get_flags() & ApplicationFlags.IS_SERVICE) == ApplicationFlags.IS_SERVICE) window.hide_on_close = true;
            }
            window.present();
        });
    }

    public void handle_uri(string jid, string query, Gee.Map<string, string> options) {
        switch (query) {
            case "join":
                show_join_muc_dialog(null, jid);
                break;
            case "message":
                Gee.List<Account> accounts = stream_interactor.get_accounts();
                Jid parsed_jid = null;
                try {
                    parsed_jid = new Jid(jid);
                } catch (InvalidJidError ignored) {
                    // Ignored
                }
                if (accounts.size == 1 && parsed_jid != null) {
                    Conversation conversation = stream_interactor.get_module(ConversationManager.IDENTITY).create_conversation(parsed_jid, accounts[0], Conversation.Type.CHAT);
                    stream_interactor.get_module(ConversationManager.IDENTITY).start_conversation(conversation);
                    controller.select_conversation(conversation);
                } else {
                    AddChatDialog dialog = new AddChatDialog(stream_interactor, stream_interactor.get_accounts());
                    dialog.set_filter(jid);
                    dialog.set_transient_for(window);
                    dialog.added.connect((conversation) => {
                        controller.select_conversation(conversation);
                    });
                    dialog.present();
                }
                break;
        }
    }

    private void create_actions() {
        SimpleAction preferences_action = new SimpleAction("preferences", null);
        preferences_action.activate.connect(show_preferences_window);
        add_action(preferences_action);
        set_accels_for_action("app.preferences", KEY_COMBINATION_SHOW_SETTINGS);

        SimpleAction preferences_account_action = new SimpleAction("preferences-account", VariantType.INT32);
        preferences_account_action.activate.connect((variant) => {
            Account? account = db.get_account_by_id(variant.get_int32());
            if (account == null) return;
            show_preferences_account_window(account);
        });
        add_action(preferences_account_action);

        SimpleAction about_action = new SimpleAction("about", null);
        about_action.activate.connect(show_about_window);
        add_action(about_action);

        SimpleAction quit_action = new SimpleAction("quit", null);
        quit_action.activate.connect(quit);
        add_action(quit_action);
        set_accels_for_action("app.quit", KEY_COMBINATION_QUIT);

        SimpleAction open_conversation_action = new SimpleAction("open-conversation", VariantType.INT32);
        open_conversation_action.activate.connect((variant) => {
            Conversation? conversation = stream_interactor.get_module(ConversationManager.IDENTITY).get_conversation_by_id(variant.get_int32());
            if (conversation != null) controller.select_conversation(conversation);
            Util.present_window(window);
        });
        add_action(open_conversation_action);

        SimpleAction open_conversation_details_action = new SimpleAction("open-conversation-details", new VariantType.tuple(new VariantType[]{VariantType.INT32, VariantType.STRING}));
        open_conversation_details_action.activate.connect((variant) => {
            int conversation_id = variant.get_child_value(0).get_int32();
            Conversation? conversation = stream_interactor.get_module(ConversationManager.IDENTITY).get_conversation_by_id(conversation_id);
            if (conversation == null) return;

            string stack_value = variant.get_child_value(1).get_string();

            var conversation_details = ConversationDetails.setup_dialog(conversation, stream_interactor, window);
            conversation_details.stack.visible_child_name = stack_value;
            conversation_details.present();
        });
        add_action(open_conversation_details_action);

        SimpleAction deny_subscription_action = new SimpleAction("deny-subscription", VariantType.INT32);
        deny_subscription_action.activate.connect((variant) => {
            Conversation? conversation = stream_interactor.get_module(ConversationManager.IDENTITY).get_conversation_by_id(variant.get_int32());
            if (conversation == null) return;
            stream_interactor.get_module(PresenceManager.IDENTITY).deny_subscription(conversation.account, conversation.counterpart);
        });
        add_action(deny_subscription_action);

        SimpleAction contacts_action = new SimpleAction("add_chat", null);
        contacts_action.activate.connect(() => {
            AddChatDialog add_chat_dialog = new AddChatDialog(stream_interactor, stream_interactor.get_accounts());
            add_chat_dialog.set_transient_for(window);
            add_chat_dialog.added.connect((conversation) => controller.select_conversation(conversation));
            add_chat_dialog.present();
        });
        add_action(contacts_action);
        set_accels_for_action("app.add_chat", KEY_COMBINATION_ADD_CHAT);

        SimpleAction conference_action = new SimpleAction("add_conference", null);
        conference_action.activate.connect(() => {
            AddConferenceDialog add_conference_dialog = new AddConferenceDialog(stream_interactor);
            add_conference_dialog.set_transient_for(window);
            add_conference_dialog.present();
        });
        add_action(conference_action);
        set_accels_for_action("app.add_conference", KEY_COMBINATION_ADD_CONFERENCE);

        SimpleAction accept_muc_invite_action = new SimpleAction("open-muc-join", VariantType.INT32);
        accept_muc_invite_action.activate.connect((variant) => {
            Conversation? conversation = stream_interactor.get_module(ConversationManager.IDENTITY).get_conversation_by_id(variant.get_int32());
            if (conversation == null) return;
            show_join_muc_dialog(conversation.account, conversation.counterpart.to_string());
        });
        add_action(accept_muc_invite_action);

        SimpleAction accept_voice_request_action = new SimpleAction("accept-voice-request", new VariantType.tuple(new VariantType[]{VariantType.INT32, VariantType.STRING}));
        accept_voice_request_action.activate.connect((variant) => {
            int conversation_id = variant.get_child_value(0).get_int32();
            Conversation? conversation = stream_interactor.get_module(ConversationManager.IDENTITY).get_conversation_by_id(conversation_id);
            if (conversation == null) return;

            string nick = variant.get_child_value(1).get_string();
            stream_interactor.get_module(MucManager.IDENTITY).change_role(conversation.account, conversation.counterpart, nick, "participant");
        });
        add_action(accept_voice_request_action);

        SimpleAction loop_conversations_action = new SimpleAction("loop_conversations", null);
        loop_conversations_action.activate.connect(() => { window.loop_conversations(false); });
        add_action(loop_conversations_action);
        set_accels_for_action("app.loop_conversations", KEY_COMBINATION_LOOP_CONVERSATIONS);

        SimpleAction loop_conversations_bw_action = new SimpleAction("loop_conversations_bw", null);
        loop_conversations_bw_action.activate.connect(() => { window.loop_conversations(true); });
        add_action(loop_conversations_bw_action);
        set_accels_for_action("app.loop_conversations_bw", KEY_COMBINATION_LOOP_CONVERSATIONS_REV);

        SimpleAction accept_call_action = new SimpleAction("accept-call", new VariantType.tuple(new VariantType[]{VariantType.INT32, VariantType.INT32}));
        accept_call_action.activate.connect((variant) => {
            int conversation_id = variant.get_child_value(0).get_int32();
            Conversation? conversation = stream_interactor.get_module(ConversationManager.IDENTITY).get_conversation_by_id(conversation_id);
            if (conversation == null) return;

            int call_id = variant.get_child_value(1).get_int32();
            Call? call = stream_interactor.get_module(CallStore.IDENTITY).get_call_by_id(call_id, conversation);
            CallState? call_state = stream_interactor.get_module(Calls.IDENTITY).call_states[call];
            if (call_state == null) return;

            call_state.accept();

            var call_window = new CallWindow();
            call_window.controller = new CallWindowController(call_window, call_state, stream_interactor);
            call_window.present();
        });
        add_action(accept_call_action);

        SimpleAction deny_call_action = new SimpleAction("reject-call", new VariantType.tuple(new VariantType[]{VariantType.INT32, VariantType.INT32}));
        deny_call_action.activate.connect((variant) => {
            int conversation_id = variant.get_child_value(0).get_int32();
            Conversation? conversation = stream_interactor.get_module(ConversationManager.IDENTITY).get_conversation_by_id(conversation_id);
            if (conversation == null) return;

            int call_id = variant.get_child_value(1).get_int32();
            Call? call = stream_interactor.get_module(CallStore.IDENTITY).get_call_by_id(call_id, conversation);
            CallState? call_state = stream_interactor.get_module(Calls.IDENTITY).call_states[call];
            if (call_state == null) return;

            call_state.reject();
        });
        add_action(deny_call_action);

        SimpleAction p_online_action = new SimpleAction("presence_online", null);
        p_online_action.activate.connect( () => {
            stream_interactor.get_module(PresenceManager.IDENTITY).send_presence(Xmpp.Presence.Stanza.SHOW_ONLINE);
            window.refresh_presence_button(Xmpp.Presence.Stanza.SHOW_ONLINE);
        });
        add_action(p_online_action);

        SimpleAction p_dnd_action = new SimpleAction("presence_dnd", null);
        p_dnd_action.activate.connect( () => {
            stream_interactor.get_module(PresenceManager.IDENTITY).send_presence(Xmpp.Presence.Stanza.SHOW_DND);
            window.refresh_presence_button(Xmpp.Presence.Stanza.SHOW_DND);
        });
        add_action(p_dnd_action);

        SimpleAction p_away_action = new SimpleAction("presence_away", null);
        p_away_action.activate.connect( () => {
            stream_interactor.get_module(PresenceManager.IDENTITY).send_presence(Xmpp.Presence.Stanza.SHOW_AWAY);
            window.refresh_presence_button(Xmpp.Presence.Stanza.SHOW_AWAY);
        });
        add_action(p_away_action);

        SimpleAction p_xaway_action = new SimpleAction("presence_xaway", null);
        p_xaway_action.activate.connect( () => {
            stream_interactor.get_module(PresenceManager.IDENTITY).send_presence(Xmpp.Presence.Stanza.SHOW_XA);
            window.refresh_presence_button(Xmpp.Presence.Stanza.SHOW_XA);
        });
        add_action(p_xaway_action);

    }

    private void show_preferences_window() {
        Ui.PreferencesWindow dialog = new Ui.PreferencesWindow() { transient_for = window };
        dialog.model.populate(db, stream_interactor);
        dialog.present();
    }

    private void show_preferences_account_window(Account account) {
        Ui.PreferencesWindow dialog = new Ui.PreferencesWindow() { transient_for = window };
        dialog.model.populate(db, stream_interactor);
        dialog.accounts_page.account_chosen(account);
        dialog.present();
    }

    private void show_about_window() {
        string? version = Dino.get_version().strip().length == 0 ? null : Dino.get_version();
        if (version != null && !version.contains("git")) {
            switch (version.substring(0, 3)) {
                case "0.2": version = @"$version - Mexican Caribbean Coral Reefs"; break;
                case "0.3": version = @"$version - Theikenmeer"; break;
                case "0.4": version = @"$version - Ilulissat"; break;
                case "0.5": version = @"$version - Alentejo"; break;
            }
        }

        Adw.AboutWindow about_window = new Adw.AboutWindow();
        about_window.application_icon = "im.dino.Dino";
        about_window.application_name = "Dino";
        about_window.issue_url = "https://github.com/dino/dino/issues";
        about_window.destroy_with_parent = true;
        about_window.transient_for = window;
        about_window.modal = true;
        about_window.title = _("About Dino");
        about_window.version = version;
        about_window.website = "https://dino.im/";
        about_window.copyright = "Copyright © 2016-2025 - Dino Team";
        about_window.license_type = License.GPL_3_0;
        about_window.present();
    }

    private void show_join_muc_dialog(Account? account, string jid) {
        Dialog dialog = new Dialog.with_buttons(_("Join Channel"), window, Gtk.DialogFlags.MODAL | Gtk.DialogFlags.USE_HEADER_BAR, _("Join"), ResponseType.OK, _("Cancel"), ResponseType.CANCEL);
        dialog.modal = true;
        Button ok_button = dialog.get_widget_for_response(ResponseType.OK) as Button;
        ok_button.add_css_class("suggested-action");
        ConferenceDetailsFragment conference_fragment = new ConferenceDetailsFragment(stream_interactor) { ok_button=ok_button };
        conference_fragment.jid = jid;
        if (account != null)  {
            conference_fragment.account = account;
        }
        Box content_area = dialog.get_content_area();
        content_area.append(conference_fragment);
        conference_fragment.joined.connect(() => {
            dialog.destroy();
        });
        dialog.response.connect((response_id) => {
            if (response_id == ResponseType.CANCEL) {
                dialog.destroy();
            }
        });
        dialog.present();
    }
}

