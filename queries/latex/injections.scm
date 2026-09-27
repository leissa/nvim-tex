;; extends

; `\begin{lstlisting}[language=Python]`: the options are not parsed, they
; are the start of the code. `nvim-tex-lstlisting!` (see
; lua/nvim-tex/injections.lua) reads the language from them and starts the
; injected code after the closing bracket.
((listing_environment
  code: (source_code) @injection.content)
  (#nvim-tex-lstlisting! @injection.content))
