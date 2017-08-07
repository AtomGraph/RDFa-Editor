# RDFa-Editor

A prototype of how RDFa annotations can be done on XHTML declaratively using client-side XSLT. Double-click on some text, enter any name in the prompt and inspect the DOM of the bold `<span>`. You should see RDFa attributes such as `about`, `content`, and `property`.

Works at least in Firefox.

Uses Saxon-CE 1.1 as XSLT 2.0 processor in the browser: http://www.saxonica.com/ce/index.xml

An updated version is also available as Saxon-JS (though not open-source): http://www.saxonica.com/saxon-js/index.xml