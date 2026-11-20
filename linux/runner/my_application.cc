#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include <cstdio>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
	GtkApplication parent_instance;
	char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static const char kAppFolderName[] = "NotePocket";
static const char kWindowStateFileName[] = "window.txt";
static const int kWindowStateValueCount = 4;
static const int kFolderPermissions = 0755;

static gchar* window_state_path() {
	return g_build_filename(g_get_user_data_dir(), kAppFolderName, kWindowStateFileName, nullptr);
}

static void restore_window_state(GtkWindow* window) {
	g_autofree gchar* path = window_state_path();
	g_autofree gchar* contents = nullptr;
	if (!g_file_get_contents(path, &contents, nullptr, nullptr)) {
		return;
	}
	int x = 0;
	int y = 0;
	int width = 0;
	int height = 0;
	if (sscanf(contents, "%d %d %d %d", &x, &y, &width, &height) != kWindowStateValueCount) {
		return;
	}
	gtk_window_set_default_size(window, width, height);
	gtk_window_move(window, x, y);
}

static gboolean save_window_state(GtkWidget* widget, GdkEvent*, gpointer) {
	GtkWindow* window = GTK_WINDOW(widget);
	int x = 0;
	int y = 0;
	int width = 0;
	int height = 0;
	gtk_window_get_position(window, &x, &y);
	gtk_window_get_size(window, &width, &height);

	g_autofree gchar* path = window_state_path();
	g_autofree gchar* folder = g_path_get_dirname(path);
	g_mkdir_with_parents(folder, kFolderPermissions);
	g_autofree gchar* contents = g_strdup_printf("%d %d %d %d", x, y, width, height);
	g_file_set_contents(path, contents, -1, nullptr);
	return FALSE;
}

static void set_window_icon(GtkWindow* window) {
	g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
	if (executable == nullptr) return;
	g_autofree gchar* folder = g_path_get_dirname(executable);
	g_autofree gchar* icon_path = g_build_filename(folder, "data", "app_icon.png", nullptr);
	gtk_window_set_icon_from_file(window, icon_path, nullptr);
}

static void first_frame_cb(MyApplication* self, FlView* view) {
	gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void my_application_activate(GApplication* application) {
	MyApplication* self = MY_APPLICATION(application);

	GtkWindow* window =
			GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
	gtk_window_set_default_size(window, 420, 800);
	restore_window_state(window);
	g_signal_connect(window, "delete-event", G_CALLBACK(save_window_state), nullptr);

	gtk_window_set_title(window, "Note Pocket");
	set_window_icon(window);

	g_autoptr(FlDartProject) project = fl_dart_project_new();
	fl_dart_project_set_dart_entrypoint_arguments(
			project, self->dart_entrypoint_arguments);

	FlView* view = fl_view_new(project);
	GdkRGBA background_color;
	gdk_rgba_parse(&background_color, "#000000");
	fl_view_set_background_color(view, &background_color);
	gtk_widget_show(GTK_WIDGET(view));
	gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

	g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
													 self);
	gtk_widget_realize(GTK_WIDGET(view));

	fl_register_plugins(FL_PLUGIN_REGISTRY(view));

	gtk_widget_grab_focus(GTK_WIDGET(view));
}

static gboolean my_application_local_command_line(GApplication* application,
																									gchar*** arguments,
																									int* exit_status) {
	MyApplication* self = MY_APPLICATION(application);
	self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

	g_autoptr(GError) error = nullptr;
	if (!g_application_register(application, nullptr, &error)) {
		g_warning("Failed to register: %s", error->message);
		*exit_status = 1;
		return TRUE;
	}

	g_application_activate(application);
	*exit_status = 0;

	return TRUE;
}

static void my_application_startup(GApplication* application) {

	G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

static void my_application_shutdown(GApplication* application) {

	G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

static void my_application_dispose(GObject* object) {
	MyApplication* self = MY_APPLICATION(object);
	g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
	G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
	G_APPLICATION_CLASS(klass)->activate = my_application_activate;
	G_APPLICATION_CLASS(klass)->local_command_line =
			my_application_local_command_line;
	G_APPLICATION_CLASS(klass)->startup = my_application_startup;
	G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
	G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
	g_set_prgname(APPLICATION_ID);

	return MY_APPLICATION(g_object_new(my_application_get_type(),
																		 "application-id", APPLICATION_ID, "flags",
																		 G_APPLICATION_NON_UNIQUE, nullptr));
}
