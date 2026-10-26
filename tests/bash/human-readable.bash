human-readable() {
	numfmt --to=iec-i --suffix=B --unit-separator=' ' $1
}

total-size() {
	du -bc "$@" | tail -1 | cut -f 1
}

size=$(total-size "$@")
human-readable $size
