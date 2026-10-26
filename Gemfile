source "https://rubygems.org"

# Scarpe from codenamev/scarpe's `editor` branch: drop, insert and opening files from Finder
# (scarpe-team/scarpe#648 and #650), --app-version (#651), and the edit box spelling support
# (codenamev/scarpe#1). Pinned to one commit; change the ref to move it.
git "https://github.com/codenamev/scarpe.git", ref: "9f23aaccd3bd8cb76ca2fd22c2fc2ff232f1b410" do
  gem "scarpe"
  gem "lacci"
  gem "scarpe-components"
end

group :test do
  gem "minitest", "~> 5.0", require: false
end
