ArchivesSpace 2.1 PUI defines styles with SCSS files in
`public/app/assets/stylesheets`. The colors of the interface are set in
`_variables.scss`, but there's no good way to customize these variables because
they are compiled and baked into the PUI's WAR file in the ArchivesSpace
distribution into, e.g., `application-7b45e...c66c1.css`. (You can't just edit
the SCSS variables in the WAR file, because they have already been compiled
into the final CSS.)

The only way I can see to customize the SCSS variables and use them is to
compile an overlay made up of all of the ArchivesSpace SCSS files. Those files,
slightly tweaked so they'll compile without some other stuff in
ArchivesSpace,are in `assets/archivesspace/` and `assets/foundation/`.

Customize the colors via the SCSS variables in
`assets/archivesspace/colors.scss`.

You don't have to compile the SCSS manually. The `assets/style.scss` file will
automatically get compiled by Rails when `/assets/style.css` is requested by a
browser.
