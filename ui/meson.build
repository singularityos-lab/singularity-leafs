vetro = find_program('vetro')

vetro_gir = []
if meson.is_subproject()
  vetro_gir = ['--gir', subproject('libsingularity').get_variable('libsingularity_gir')]
endif
main_ui = custom_target(
  'main_ui_gen',
  input: 'main.vetro',
  output: 'main.ui',
  command: [vetro] + vetro_gir + ['--in', '@INPUT@', '--out', '@OUTPUT@'],
  install: false,
  build_by_default: true
)