project('singularity-leafs', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

gnome = import('gnome')

gtk_dep            = dependency('gtk4')
gee_dep            = dependency('gee-0.8')
vte_dep            = dependency('vte-2.91-gtk4')
json_dep           = dependency('json-glib-1.0')

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

subdir('ui')

resources = gnome.compile_resources(
  'singularity-leafs-resources',
  'resources/dev.sinty.leafs.gresource.xml',
  source_dir: [meson.current_source_dir(), meson.current_build_dir()],
  dependencies: main_ui
)

executable('singularity-leafs',
  [
    'src/main.vala',
    'src/ssh_session.vala',
    'src/ssh_dialog.vala',
    'src/leaf_pane.vala',
    'src/window.vala',
    'src/app.vala',
    resources,
  ],
  dependencies: [gtk_dep, gee_dep, vte_dep, json_dep, libsingularity_dep,
                 meson.get_compiler('c').find_library('m', required: true)],
  vala_args: ['--pkg=posix'],
  install: true
)

install_data('data/dev.sinty.leafs.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data('data/dev.sinty.leafs.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

install_data('data/dev.sinty.leafs.json',
  install_dir: get_option('datadir') / 'singularity' / 'app-settings'
)

install_data('data/icons/dev.sinty.leafs.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)