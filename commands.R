setwd(‘D:/Users/rdp/Desktop’)

job=example=getJob('job_1446118271192_0092')
knit('example.Rmd')
markdownToHTML('example.md','exampleJob.html')
