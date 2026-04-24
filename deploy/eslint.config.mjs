import stylistic from '@stylistic/eslint-plugin'
import unicorn from 'eslint-plugin-unicorn'
import tseslint from 'typescript-eslint'

export default tseslint.config(
  { ignores: ['node_modules/'] },
  tseslint.configs.strictTypeChecked,
  unicorn.configs['flat/recommended'],
  stylistic.configs.customize({
    indent: 2,
    quotes: 'single',
    semi: false,
    jsx: false,
  }),
  {
    languageOptions: {
      parserOptions: {
        project: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      '@stylistic/padding-line-between-statements': ['error',
        { blankLine: 'always', prev: 'block-like', next: '*' },
      ],
      '@typescript-eslint/restrict-template-expressions': ['error', { allowNumber: true }],
      'unicorn/prefer-module': 'off',            // CommonJS project
      'unicorn/no-process-exit': 'off',          // intentional process.exit usage
      'unicorn/prevent-abbreviations': 'off',    // abbreviations used throughout
      'unicorn/prefer-top-level-await': 'off',   // CommonJS, no top-level await
    },
  },
)
