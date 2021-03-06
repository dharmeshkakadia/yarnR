list.of.packages <- c("ggplot2", "RCurl", "rjson","knitr","markdown","jsonlite")
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages, repos='http://cran.us.r-project.org')

lapply(list.of.packages,function(x){library(x,character.only=TRUE)}) 
#from http://r.789695.n4.nabble.com/Load-Libraries-from-list-td4199976.html

# It returns all the data of a job with specified jobId and specified history server
# The historyServer is in format "hostname:port"

# You might need to install  libcurl for RCurl installation
# sudo apt-get -y install libcurl4-gnutls-dev

getJob <- function(jobId, historyServer="headnodehost:19888")
{
	job <- list()
	url<-paste("http://",historyServer,"/ws/v1/history/mapreduce/jobs/",jobId, sep="")
	job$job <- rjson::fromJSON(getURL(url,httpheader = c(Accept="application/json")))$job
	
	# url<-paste("http://",historyServer,"/ws/v1/history/mapreduce/jobs/",jobId,"/conf", sep="")
	# job$conf<- transposeListOfLists(fromJSON(getURL(url,httpheader = c(Accept="application/json")))$conf$property)
	
	url<-paste("http://",historyServer,"/ws/v1/history/mapreduce/jobs/",jobId,"/tasks", sep="")
	job$tasks <- transposeListOfLists(rjson::fromJSON(getURL(url,httpheader = c(Accept="application/json")))$tasks$task)
	attempts<-list()
	for(i in 1:length(job$tasks$successfulAttempt))
	{
		attempt<-job$tasks$successfulAttempt[i]
		tryCatch({
 			url<-paste(historyServer, "/ws/v1/history/mapreduce/jobs/",jobId,"/tasks/",job$tasks$id[i], "/attempts/",attempt,sep="")
			attempts[[i]]<-rjson::fromJSON(getURL(url,httpheader = c(Accept="application/json")))$taskAttempt
 	 	},error = function(e) {}
 		)
		
	}
	job$attempts<-transposeListOfLists(attempts)
	class(job)<-"mrjob"
	job
}

transposeListOfLists <- function(listoflist)
{
	result<-list()
	for(i in 1:length(listoflist))
	{
		for(j in 1:length(listoflist[[i]]))
		{
			result[[names(listoflist[[i]][j])]]<-c(result[[names(listoflist[[i]][j])]],listoflist[[i]][[j]])
		}	
	}	
	result
}

readzip <- function(zipfile) {
    # Create a name for the dir where we'll unzip
    zipdir <- tempfile()
    # Create the dir using that name
    dir.create(zipdir)
    # Unzip the file into the dir
    unzip(zipfile, exdir=zipdir)
    # Get the files into the dir
    allfiles <- list.files(zipdir)
    # Throw an error if there's more than one
    if(length(allfiles)<1) stop("No data file inside zip")
    # Get the full name of the file
    task_files=allfiles[grepl("tasks_part_.*.json",allfiles)]
    wd=getwd()
    setwd(zipdir)
    tasks <- list()
    #https://cran.r-project.org/web/packages/jsonlite/vignettes/json-paging.html
    for(i in 1:length(task_files)){
      mydata <- fromJSON(task_files[i])
      message("Retrieving file tasks_part_", i)
      tasks[[i+1]] <- mydata$tasks
    }
    setwd(wd)
    all_tasks <- rbind.pages(tasks)
}

# This is useful for plotting downloaded ZIP

plotTezZip <- function(dag,title="Tez plot" , interval=1000, xtick=100, ytick=100,savefile="tezdag"){
	range=length(dag$otherinfo$status)
	vertex = unique(matrix(unlist(strsplit(dag$entity,"_")),ncol = 6, byrow=T)[,5]) #help from https://stat.ethz.ch/pipermail/r-help/2010-January/224852.html
	# task_1446542009204_0186_1_05_000552
	tasks=data.frame(time=rep(0,range),total=rep(0,range))
	count=1	
	for (i in seq(from=min(dag$otherinfo$startTime)-1, to=max(dag$otherinfo$endTime)+interval, by=interval)){
		tasks[count,"time"]=count
		tasks[count,"total"]=length(which(dag$otherinfo$startTime < i & dag$otherinfo$endTime > (i+interval) ))
		for (j in 1:length(vertex)) {
			tasks[count,paste("task_",vertex[j],sep="")]=length(which(grepl(paste("_",vertex[j],"_",sep=""),dag$entity) & dag$otherinfo$startTime < i & dag$otherinfo$endTime > (i+interval) ))	
		}
		count=count+1
	}

	library(reshape2) 
	data2 <- melt(tasks, id = "time")
	p = ggplot(data2, aes(x = time, y = value, color = variable)) + geom_line() + theme(legend.title=element_blank()) + scale_x_continuous(minor_breaks = round(seq(0, length(tasks$time), by = xtick),1)) + scale_y_continuous(minor_breaks = round(seq(0, max(tasks$total)*1.1, by = ytick),1)) +xlab(paste("Time (",interval, " ms)")) + ylab("Number of Tasks") +ggtitle(title)
	if(hasArg(savefile)){
		ggsave(plot=p,file=savefile)
		print(sprintf("Saved plot as %s",savefile))
	}
	p
}

# This is used by Rmd file to gernereate HTML page with the plot
myTezPlot2 <- function(dag,title="Tez plot" , interval=1000, xtick=100, ytick=100,savefile="tezdag"){
	range=length(dag$tasks$vertexId)
	vertex = unique(dag$tasks$vertexId) #help from https://stat.ethz.ch/pipermail/r-help/2010-January/224852.html
	# task_1446542009204_0186_1_05_000552
	tasks=data.frame(time=rep(0,range),total=rep(0,range))
	count=1	
	for (i in seq(from=min(dag$tasks$startTime)-1, to=max(dag$tasks$endTime)+interval, by=interval)){
		tasks[count,"time"]=count
		tasks[count,"total"]=length(which(dag$tasks$startTime < i & dag$tasks$endTime > (i+interval) ))
		for (j in 1:length(vertex)) {
			tasks[count,vertex[j]]=length(which(vertex[j] == dag$tasks$vertexId & dag$tasks$startTime < i & dag$tasks$endTime > (i+interval) ))	
		}
		count=count+1
	}

	library(reshape2) 
	data2 <- melt(tasks, id = "time")
	p = ggplot(data2, aes(x = time, y = value, color = variable)) + geom_line() + theme(legend.title=element_blank()) + scale_x_continuous(minor_breaks = round(seq(0, length(tasks$time), by = xtick),1)) + scale_y_continuous(minor_breaks = round(seq(0, max(tasks$total)*1.1, by = ytick),1)) +xlab(paste("Time (",interval, " ms)")) + ylab("Number of Tasks") +ggtitle(title)
	if(hasArg(savefile)){
		ggsave(plot=p,file=savefile)
		print(sprintf("Saved plot as %s",savefile))
	}
	p
}

getTezDag <- function(dagId, timelineServer="headnodehost:8188")
{
	dag <- list()
	url<-paste("http://",timelineServer,"/ws/v1/timeline/TEZ_DAG_ID/",dagId, sep="")
	dag$dag <- rjson::fromJSON(getURL(url,httpheader = c(Accept="application/json")))
	
	dag$tasks<- data.frame(matrix(nrow=length(dag$dag$otherinfo$vertexNameIdMapping),ncol=4))
	
	colnames(dag$tasks) <- c("vertexId","taskId", "startTime", "endTime")
	
	count=1
	for(i in 1:length(dag$dag$otherinfo$vertexNameIdMapping))
	{
		vertexId<-dag$dag$otherinfo$vertexNameIdMapping[[i]]
		url<-paste("http://",timelineServer,"/ws/v1/timeline/TEZ_VERTEX_ID/",vertexId, sep="")
		temp <- rjson::fromJSON(getURL(url,httpheader = c(Accept="application/json")))
		
		for(j in 1:length(temp$relatedentities$TEZ_TASK_ID))
		{
 			taskUrl<-paste("http://",timelineServer,"/ws/v1/timeline/TEZ_TASK_ID/",temp$relatedentities$TEZ_TASK_ID[j], sep="")
			t <- rjson::fromJSON(getURL(taskUrl,httpheader = c(Accept="application/json")))
			dag$tasks[count,1]=vertexId
			dag$tasks[count,2]=temp$relatedentities$TEZ_TASK_ID[j]
			dag$tasks[count,3]=t$otherinfo$startTime
			dag$tasks[count,4]=t$otherinfo$endTime
			count <- count + 1
 	 	}
	}
	class(dag)<-"tezdag"
	dag
}

myplot <- function(job,title="" , interval=1000, xtick=100, ytick=100){
	tasks=getAllCounters(job,interval)
	ggplot(data=tasks)+theme(legend.title=element_blank()) + scale_x_continuous(minor_breaks = round(seq(0, length(tasks$time), by = xtick),1)) + scale_y_continuous(minor_breaks = round(seq(0, max(tasks$total)*1.1, by = ytick),1)) +geom_area(aes(x=time,y=total),fill="darkgrey")+ geom_line(aes(x=time,y=map,colour="map")) +geom_line(aes(x=time,y=shuffle,colour="shuffle")) +geom_line(aes(x=time,y=merge,colour="merge")) +geom_line(aes(x=time,y=reduceTasks,colour="reduceTasks")) +xlab(paste("Time (",interval, " ms)")) + ylab("Number of Tasks") + ggtitle(paste(title," ",job$job$id))
}
 
getAllCounters <- function(job,interval=1000,count=1){
	range=length(job$tasks$id)+10
	tasks=data.frame(time=rep(0,range),map=rep(0,range),shuffle=rep(0,range),merge=rep(0,range),reduce=rep(0,range),total=rep(0,range),reduceTasks=rep(0,range),reduceAttempts=rep(0,range))
	# count=1
	for (i in seq(from=min(job$tasks$startTime)-1, to=max(job$tasks$finishTime)+interval, by=interval)){
		tasks[count,"time"]=count
		tasks[count,"total"]=length(which(job$attempts$startTime < i & job$attempts$finishTime > (i+interval) ))
		tasks[count,"map"] = length(which(job$attempts$startTime < i & job$attempts$finishTime > i+interval & job$tasks$type == "MAP"))
		tasks[count,"shuffle"]= length(which(job$tasks$type == "REDUCE" & job$tasks$startTime < i & job$tasks$finishTime > (i+interval) & job$attempts$startTime < i & job$attempts$shuffleFinishTime > (i+interval)))
		tasks[count,"merge"]= length(which(job$tasks$type == "REDUCE" & job$tasks$startTime < i & job$tasks$finishTime > (i+interval) & job$attempts$shuffleFinishTime < i & job$attempts$mergeFinishTime > (i+interval)))
		tasks[count,"reduceTasks"] = length(which(job$tasks$type == "REDUCE" & job$attempts$startTime < i & job$attempts$finishTime > (i+interval)))
		count=count+1
	}
	tasks
}

plotTotalCompletedTasks <- function(job,interval=1000){
	tasks=rep(0,length(job$tasks$id)+10)
	count=1
	total=0;
	for (i in seq(from=min(job$attempts$startTime)-1, to=max(job$attempts$finishTime)+interval, by=interval)){
		total = total + length(which(job$attempts$finishTime > i  & job$attempts$finishTime < (i+interval) ))
		tasks[count] = total;
		count=count+1
	}
	tasks
}

plotTotalCompletedTasksWithGrid <- function(job,interval=1000) {
	tasks=plotTotalCompletedTasks(job,interval)
	plot(1:length(tasks), tasks, xlab=paste("Time (",interval, " ms)"), ylab="Task completed", type="l")
	abline(v=seq(1,length(tasks),1000),lty=2,col="blue")
	abline(h=seq(1,max(tasks)+101,100),lty=2,col="blue")
	abline(h=seq(1,max(tasks),500),lty=2,col="red")
}
