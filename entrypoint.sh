echo ":foreman_url: $FOREMAN_URL" >> config/settings.yml
exec bundle exec ruby bin/smart-proxy
