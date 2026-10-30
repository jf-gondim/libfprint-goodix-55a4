# Sphinx configuration for the Goodix 27c6:55a4 driver documentation.
# Layout follows ssc-raft-apps-docs: sphinx_rtd_theme + myst_parser, with the
# pages under source/ and the existing Markdown notes pulled in as they are.

project = 'goodix-27c6-55a4-fingerprint-linux'
copyright = '2026, Hydrogell and contributors'
author = 'Hydrogell and contributors'

extensions = [
    'sphinx_rtd_theme',
    'myst_parser',
]

source_suffix = {
    '.rst': 'restructuredtext',
    '.md': 'markdown',
}

templates_path = ['_templates']
exclude_patterns = ['_build', 'source/about.rst']  # about.rst is .. include::d by index.rst

html_theme = 'sphinx_rtd_theme'
