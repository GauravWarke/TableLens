export default [{
  files: ['web/*.mjs'],
  languageOptions: {
    ecmaVersion: 2022,
    sourceType: 'module',
    globals: Object.fromEntries([
      'document', 'window', 'navigator', 'URL', 'Image', 'setTimeout', 'console'
    ].map(name => [name, 'readonly']))
  },
  rules: {
    'no-undef': 'error',
    'no-unused-vars': 'error',
    'no-unreachable': 'error',
    'no-dupe-keys': 'error',
    'no-fallthrough': 'error',
    'no-constant-condition': 'error',
    'no-redeclare': 'error',
    'eqeqeq': 'error'
  }
}];
