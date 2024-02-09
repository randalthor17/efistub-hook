.PHONY: install

install:
	install -Dm644 efistub.action /etc/dnf/plugins/post-transaction-actions.d/efistub.action
	install -Dm755 efistub.sh /usr/bin/efistub
