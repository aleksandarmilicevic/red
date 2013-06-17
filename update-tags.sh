echo "copying RUBY_TAGS to local TAGS"
cp ~/.rvm/rubies/ruby-1.9.3-p327/lib/ruby/RUBY_TAGS TAGS

echo "appending project tags"
ctags-exuberant -a -e -f TAGS --tag-relative -R app lib vendor
