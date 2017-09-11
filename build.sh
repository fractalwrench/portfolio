# Generate files
rm -rf /public;
hugo;

# Minify html
html-minifier --collapse-whitespace --remove-comments --remove-optional-tags --remove-redundant-attributes --remove-script-type-attributes --remove-tag-whitespace --use-short-doctype --input-dir public --output-dir public --file-ext html

# Minify css
for f in public/css/*.css; do csso -i $f -o $f; done

# Minify js
for f in public/js/*.js; do uglifyjs --compress --mangle -o $f -- $f; done

zip -r public.zip public;
