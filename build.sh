# Generate files
rm -rf /deploy;
cp -r public deploy
hugo;

# Minify html
html-minifier --collapse-whitespace --remove-comments --remove-optional-tags --remove-redundant-attributes --remove-script-type-attributes --remove-tag-whitespace --use-short-doctype --input-dir deploy --output-dir deploy --file-ext html

# Minify css
for f in deploy/css/*.css; do csso -i $f -o $f; done

# Minify js
for f in deploy/js/*.js; do uglifyjs --compress --mangle -o $f -- $f; done

zip -r deploy.zip deploy;
