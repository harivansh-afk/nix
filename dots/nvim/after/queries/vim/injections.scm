;extends
(bang_filter_statement
  (command) @injection.content
  (#set! injection.language "bash")
  (#set! injection.include-children))
