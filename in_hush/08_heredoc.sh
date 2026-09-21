cat <<- 'EOF_QUOTED'
	\${escaped}
	`echo backtick_ignored`
EOF_QUOTED

cat <<- EOF_UNQUOTED
	Tab stripped content
	$(echo embedded_subshell)
EOF_UNQUOTED
