vetro = find_program('vetro')
main_ui = custom_target(
  'main_ui_gen',
  input: 'main.vetro',
  output: 'main.ui',
  command: [vetro, '--in', '@INPUT@', '--out', '@OUTPUT@'],
  install: false,
  build_by_default: true
)