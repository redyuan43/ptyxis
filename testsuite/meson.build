test_env = [
  'G_TEST_SRCDIR=@0@'.format(meson.current_source_dir()),
  'G_TEST_BUILDDIR=@0@'.format(meson.current_build_dir()),
  'G_DEBUG=gc-friendly',
  'GSETTINGS_BACKEND=memory',
  'MALLOC_CHECK_=2',
]

testsuite_c_args = [
  '-DG_LOG_DOMAIN="ptyxis"',
  '-DDISABLE_AGENT_ENTRY_POINT',
  '-DG_ENABLE_DEBUG',
  '-UG_DISABLE_ASSERT',
  '-UG_DISABLE_CAST_CHECKS',
]

testsuite = {
  'test-podman' : {},
  'test-util' : {
    'sources' : [
      '../src/ptyxis-util.c',
    ],
    'deps' : [
      dependency('gio-unix-2.0', version: glib_req),
      dependency('vte-2.91-gtk4', version: vte_req),
    ],
  },
}

testsuite_deps = [
  ptyxis_agent_deps,
]

foreach test, params: testsuite
  test_exe = executable(test,
    ['@0@.c'.format(test)] + params.get('sources', ptyxis_agent_sources),
                 c_args: testsuite_c_args,
           dependencies: params.get('deps', testsuite_deps),
    include_directories: [include_directories('..'), include_directories('.'), include_directories('../agent')],
  )
  if not params.get('skip', false)
    test(test, test_exe, env: test_env)
  endif
endforeach
