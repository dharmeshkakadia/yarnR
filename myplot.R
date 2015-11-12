list.of.packages <- c("ggplot2", "RCurl", "rjson","knitr","markdown")
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages, repos='http://cran.us.r-project.org')

lapply(list.of.packages,function(x){library(x,character.only=TRUE)}) 
#from http://r.789695.n4.nabble.com/Load-Libraries-from-list-td4199976.html
# It returns all the data of a job with specified jobId and specified history server
# The historyServer is in format "hostname:port"

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

saveJob <- function(jobId){
#p <- p + scale_fill_brewer()
	print(jobId)
	tryCatch({
 	job=getJob(jobId,"localhost:19888")
 	 save(file=paste(jobId,".RData",sep = ""),job)
 	 	},error = function(e) {}
 		)
}

getJobSummary <- function(jobId, historyServer)
{
	job <- list()
	url<-paste("http://",historyServer,"/ws/v1/history/mapreduce/jobs/",jobId, sep="")
	job$job <- rjson::fromJSON(getURL(url,httpheader = c(Accept="application/json")))$job
	
	url<-paste("http://",historyServer,"/ws/v1/history/mapreduce/jobs/",jobId,"/conf", sep="")
	job$conf<- transposeListOfLists(rjson::fromJSON(getURL(url,httpheader = c(Accept="application/json")))$conf$property)
	
	url<-paste("http://",historyServer,"/ws/v1/history/mapreduce/jobs/",jobId,"/counters", sep="")
	job$counters<- transposeListOfLists(rjson::fromJSON(getURL(url,httpheader = c(Accept="application/json")))$jobCounters)
	
	class(job)<-"mrjob"
	job
}


# This function plot the number of active reducers in different phases (shuffle, merge, reduce)at every time point when this number changes
plotActiveReduceTasksNumDetaileddata <- function(job, relative=TRUE)
{
	if (relative)
	{
		indices<-which(job$tasks$type=="REDUCE")
		offset <- min(job$tasks$startTime[indices])
	}
	else
		offset<-0
	numsSP <- getActiveShufflePhaseReducerNum(job, offset )
	numsMP <- getActiveMergePhaseReducerNum(job, offset )
	numsRP <- getActiveReducePhaseReducerNum(job, offset )
	yrange<-range(c(numsSP[,2], numsMP[,2], numsRP[,2]))
	xrange<-range(c(numsSP[,1], numsMP[,1], numsRP[,1]))
	plotActiveTasksNum(numsSP, replot=FALSE, col="darkorange", xlim=xrange, ylim=yrange)
	plotActiveTasksNum(numsMP, replot=TRUE, col="magenta")
	plotActiveTasksNum(numsRP, replot=TRUE, col="blue")
}

getTaskCounters <- function(jobId, historyServer)
{
	result<-list()
	url<-paste("http://",historyServer,"/ws/v1/history/mapreduce/jobs/",jobId,"/tasks", sep="")
	tasks <- transposeListOfLists(rjson::fromJSON(getURL(url,httpheader = c(Accept="application/json")))$tasks$task)
	for(i in 1:length(tasks$successfulAttempt))
	{
		attempt<-tasks$successfulAttempt[i]
		url<-paste(historyServer, "/ws/v1/history/mapreduce/jobs/",jobId,"/tasks/",tasks$id[i], "/attempts/",attempt,"/counters",sep="")
		counter<-rjson::fromJSON(getURL(url,httpheader = c(Accept="application/json")))$jobTaskAttemptCounters$taskAttemptCounterGroup
		for( j in 1:length(counter))
		{
			groups<-counter[[j]]
			for(g in 1:length(groups$counter))
			{
				key<-paste(tail(strsplit(groups$counterGroupName,"\\.")[[1]],n=1),groups$counter[[g]]$name,sep=".");
				value<-groups$counter[[g]]$value
				if (is.null(result[[key]]))
					result[[key]]<-c(value)
				else
					result[[key]]<-c(result[[key]],value)
			}
		}
	}
	result
}


# This is a helper function that is used while loading the job from historyServer
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

getActiveTasksNum <- function(job, indices=1:length(job$tasks$startTime), minTime=NULL)
{
	times<-rbind(cbind(job$tasks$startTime[indices],rep(1,length(indices))),
 		cbind(job$tasks$finishTime[indices],rep(-1,length(indices))))
	nums <- calcNums(times, minTime)
	nums
}

getActiveShufflePhaseReducerNum <- function(job, minTime=NULL)
{
	indices<-which(job$tasks$type=="REDUCE")
	times<-rbind(cbind(job$tasks$startTime[indices],rep(1,length(indices))),
 		cbind(job$attempts$shuffleFinishTime,rep(-1,length(job$attempts$shuffleFinishTime))))
	nums <- calcNums(times, minTime)
	nums
}

getActiveMergePhaseReducerNum <- function(job, minTime=NULL)
{
	times<-rbind(cbind(job$attempts$shuffleFinishTime,rep(1,length(job$attempts$shuffleFinishTime))),
 		cbind(job$attempts$mergeFinishTime,rep(-1,length(job$attempts$mergeFinishTime))))
	nums <- calcNums(times, minTime)
	nums
}

getActiveReducePhaseReducerNum <- function(job, minTime=NULL)
{
	indices<-which(job$tasks$type=="REDUCE")
	times<-rbind(cbind(job$attempts$mergeFinishTime,rep(1,length(job$attempts$mergeFinishTime))),
 		cbind(job$tasks$finishTime[indices],rep(-1,length(indices))))
	nums <- calcNums(times, minTime)
	nums
}


plotActiveTasksNum <- function(nums, replot=FALSE, col="black", xlim=NULL, ylim=NULL)
{
	if (replot)
		points(nums, type="l", xlab="time (ms)",ylab="number of tasks", col=col)
	else
		plot(nums, type="l", xlab="time (ms)",ylab="number of tasks", col=col, xlim=xlim, ylim=ylim)
}

# This function calculates the number of tasks if times are given as (time, +-1) pairs
calcNums <- function(times, minTime=NULL)
{
	sortedtimes<-times[order(times[,1]),]
	toplot<-sortedtimes
	if ( is.null(minTime) )
		toplot[,1]<-sortedtimes[,1]-sortedtimes[1,1]
	else
		toplot[,1]<-sortedtimes[,1]-minTime
	nums<-matrix(nrow=0,ncol=2)
	num<-0
	for(i in 1:nrow(toplot))
	{
		num<-num+toplot[i,2]
		nums<-rbind(nums,c(toplot[i,1],num))
	}
	nums
}

plotActiveMRTasksNumdata <- function(job, main, relative=TRUE)
{
	if (relative)
	{
		indices<-which(job$tasks$type=="MAP")
		offset <- min(job$tasks$startTime[indices])
	}
	else
		offset<-0

	numT <- getActiveTasksNum(job)	
	numsM <- getActiveTasksNum(job, which(job$tasks$type=="MAP"),offset)
	numsSP <- getActiveShufflePhaseReducerNum(job, offset)
	numsMP <- getActiveMergePhaseReducerNum(job, offset)
	numsRP <- getActiveReducePhaseReducerNum(job, offset)
	
	yrange<-range(c(numsM[,2], numsSP[,2], numsMP[,2], numsRP[,2]))
	xrange<-range(c(numsM[,1], numsSP[,1], numsMP[,1], numsRP[,1]))
	
	plot(NA,xlim=xrange, ylim=yrange,xlab = "Time(ms)",ylab = "Tasks", main=main)

	polygon(numT, col="grey")
	plotActiveTasksNum(numsM, replot=TRUE, col="green")
	plotActiveTasksNum(numsSP, replot=TRUE, col="darkorange")
	plotActiveTasksNum(numsMP, replot=TRUE, col="magenta")
	plotActiveTasksNum(numsRP, replot=TRUE, col="blue")

	legend("topright","1:length(NUmT),numT",c("total","map","shuffle","merge","reduce"),lty = c(2,1,1,1,1),lwd=c(10,2.5,2.5,2.5,2.5),col=c("grey", "green", "darkorange","magenta","blue"))
}

## example : myplot(getJob("job_1422144602418_1117","headnodehost:19888"))
myplot_old <- function(job){
	total=rep(0,length(job$tasks$id)+10)
	reduce=rep(0,length(job$tasks$id)+10)
	map=rep(0,length(job$tasks$id)+10)
	count=0
	 for (i in seq(from=min(job$tasks$startTime)-1, to=max(job$tasks$finishTime)+100, by=100)){
	total[count]=length(which(job$tasks$startTime < i & job$tasks$finishTime > i+100 ))
	map[count] = length(which(job$tasks$startTime < i & job$tasks$finishTime > i+100 & job$tasks$type == "MAP"))
	reduce[count] = length(which(job$tasks$startTime < i & job$tasks$finishTime > i+100 & job$tasks$type == "REDUCE"))
	count=count+1
	}

	plot(1:length(total),total,type="l",xlab = "Time(100ms)",ylab = "Containers")
	lines(1:length(map),map,col="red")
	lines(1:length(reduce),reduce,col="blue")

	legend("topright","1:length(total),total",c("total","map","reduce"),lty = c(1,1,1),lwd=c(2.5,2.5,2.5),col=c("black","red","blue"))
}


#for(i in seq(2916,3088)){
#    saveJob(sprintf("job_1434371604583_%04d",i))
#}


plotActiveMRTasksNumdata2 <- function(job, main)
{
	numT <- getActiveTasksNum(job, minTime=0)	
	numsM <- getActiveTasksNum(job, which(job$tasks$type=="MAP"),0)
	numsSP <- getActiveShufflePhaseReducerNum(job, 0)
	numsMP <- getActiveMergePhaseReducerNum(job, 0)
	numsRP <- getActiveReducePhaseReducerNum(job, 0)
	
	ggplot()+geom_line(data=numT, aes(x=times, y=tasks, colour="total"))+geom_line(data=numsM, aes(x=times, y=tasks, colour="maps"))+geom_line(data=numsSP, aes(x=times, y=tasks, colour="shuffle"))+geom_line(data=numsMP, aes(x=times, y=tasks, colour="merge"))+geom_line(data=numsRP, aes(x=times, y=tasks, colour="reduce"))
}



myplot <- function(job,title="" , interval=1000, xtick=100, ytick=100){
	tasks=getAllCounters(job,interval)
	ggplot(data=tasks)+theme(legend.title=element_blank()) + scale_x_continuous(breaks = round(seq(0, length(tasks$time), by = xtick),1)) + scale_y_continuous(breaks = round(seq(0, max(tasks$total)*1.1, by = ytick),1)) +geom_area(aes(x=time,y=total),fill="darkgrey")+ geom_line(aes(x=time,y=map,colour="map")) +geom_line(aes(x=time,y=shuffle,colour="shuffle")) +geom_line(aes(x=time,y=merge,colour="merge")) +geom_line(aes(x=time,y=reduceTasks,colour="reduceTasks")) +xlab(paste("Time (",interval, " ms)")) + ylab("Number of Tasks") + ggtitle(paste(title," ",job$job$id))
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

myplotSimple <- function(job,interval=1000){
	total=rep(0,length(job$tasks$id)+10)
	reduce=rep(0,length(job$tasks$id)+10)
	map=rep(0,length(job$tasks$id)+10)
	shuffle=rep(0,length(job$tasks$id)+10)
	merge=rep(0,length(job$tasks$id)+10)

	count=0
	 for (i in seq(from=min(job$tasks$startTime)-1, to=max(job$tasks$finishTime)+100, by=100)){
	total[count]=length(which(job$tasks$startTime < i & job$tasks$finishTime > i+100 ))
	map[count] = length(which(job$tasks$startTime < i & job$tasks$finishTime > i+100 & job$tasks$type == "MAP"))
	reduce[count] = length(which(job$tasks$startTime < i & job$tasks$finishTime > i+100 & job$tasks$type == "REDUCE"))
	count=count+1
	}

	plot(1:length(total),total,type="l", xaxt="n", xlab = "Time(100ms)",ylab = "Containers")
	#plot(1:length(total),total,type="l",xaxt="n")
	axis(1, at = seq(10, 200, by = 10), las=2)

	lines(1:length(map),map,col="red")
	lines(1:length(reduce),reduce,col="blue")

	legend("topright","1:length(total),total",c("total","map","reduce"),lty = c(1,1,1),lwd=c(2.5,2.5,2.5),col=c("black","red","blue"))
}

## example : myplot(getJob("job_1422144602418_1117","headnodehost:19888"))
myplot2 <- function(job,interval=1000){
	tasks=rep(0,length(job$tasks$id)+10)
	count=1
	total=0;
	for (i in seq(from=min(job$attempts$startTime)-1, to=max(job$attempts$finishTime)+interval, by=interval)){
		tasks[count] = length(which(job$attempts$finishTime > i  & job$attempts$finishTime < (i+interval) ))
		count=count+1
	}

	plot(1:length(tasks), tasks, xlab=paste("Time (",interval, " ms)"), type="l")
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

getMapElapsedTimes <- function(job){
	job$attempts$elapsedTime[job$attempts$type=="MAP"]
}

getReduceElapsedTimes <- function(job){
	job$attempts$elapsedTime[job$attempts$type=="REDUCE"]
}


############################################

#predictAndPLot<-function(x,y,power) {
	#data=data.frame(x,y)
	#return(nls(y~(b*x)^power, data=data, start=list(b=min(data$y),power=power), control=nls.control(maxiter=100000,tol=0.1)))
	#print(summary(eq))
	# print(ggplot()+geom_point(aes(x=x,y=y))+geom_line(aes(x=x, y=predict(eq, list(x = x)))))
	#return(geom_line(aes(x=data$x, y=predict(eq, list(x = data$x))),col="red"))
#}

# predictAndPLot2<-function(x,y) {
# 	data=data.frame(x,y)
# 	eq2=lm(y~x, data=data)
# 	print(summary(eq2))
# 	return(geom_line(aes(x=data$x, y=predict(eq2, list(x = data$x)))))
# }

#  for (i in seq(0,5,0.5)){
#  	tryCatch(
#  		print(summary(nls(y~(b*x)^power, data=data, start=list(b=max(data$y),power=1), control=nls.control(maxiter=100000,tol=0.1))))
#  		,error = function(e){
#  			print(e)
#  		}
#  		)
#  }


# aval=lapply(seq(0,5,0.5), function(i){
# 	nls(y~(b*x)^power, data=data, start=list(b=max(data$y),power=i), control=nls.control(maxiter=100000,tol=0.1,warnOnly=TRUE)
# 		)})

# cat(coef(eqs[[2]])["b"],"\t",coef(eqs[[2]])["power"]


# #eqs <- rep(NULL, 10)
# #eqs <- rep(list(m="", data="", call="", na.action="", dataClasses="", model="", weights="", convInfo="", control="", convergence="", message=""), 10)
# data <- read.csv("C:/Users/t-dhkaka/Desktop/test.csv")
# data
# count=1
# eqs <- list()
# for (i in seq(0,5,0.5)){
# 	eqs[[count]]=tryCatch(
# 	{
# 		#nls(y~(b*x)^power, data=data, start=list(b=max(data$y),power=i), control=nls.control(maxiter=100000,tol=0.1))
# 		nls(y~b*(x^power), data=data, start=list(b=max(data$y),power=i), control=nls.control(maxiter=100000,tol=0.1))
# 	},error=function(x) {
# 		print(x)
# 		return(NULL)
# 	}
# 	)
#  	count=count+1
# }

# cat("powerStartValue","\tb","\tpower","\tTolerance","predictedValue","\n")
# cat("=====================================================")
# count=1
# for (powerStart in seq(0,5,0.5)){
# 	if(is.null(eqs[[count]])){
# 		cat(powerStart,"\t","NA","\t","NA","\t","NA","\t","NA","\n")
# 	}else{
# 		cat(powerStart,"\t",coef(eqs[[count]])["b"],"\t",coef(eqs[[count]])["power"],"\t",eqs[[2]]$convInfo$finTol,"\t",predict(eqs[[count]],data.frame(x=100)),"\n")
# 	}
# 	count=count+1
# }

# p <- ggplot()+geom_point(aes(x=data$x,y=data$y))
#  if(!is.null(eqs[[1]])){p <- p+geom_line(aes(x=1:100, y=predict(eqs[[1]], list(x = 1:100))),colour="1")}
#  if(!is.null(eqs[[2]])){p <- p+geom_line(aes(x=1:100, y=predict(eqs[[2]], list(x = 1:100))),colour="2")}
#  if(!is.null(eqs[[3]])){p <- p+geom_line(aes(x=1:100, y=predict(eqs[[3]], list(x = 1:100))),colour="3")}
#  if(!is.null(eqs[[4]])){p <- p+geom_line(aes(x=1:100, y=predict(eqs[[4]], list(x = 1:100))),colour="4")}
#  if(!is.null(eqs[[5]])){p <- p+geom_line(aes(x=1:100, y=predict(eqs[[5]], list(x = 1:100))),colour="5")}
#  if(!is.null(eqs[[6]])){p <- p+geom_line(aes(x=1:100, y=predict(eqs[[6]], list(x = 1:100))),colour="6")}
#  if(!is.null(eqs[[7]])){p <- p+geom_line(aes(x=1:100, y=predict(eqs[[7]], list(x = 1:100))),colour="7")}
#  if(!is.null(eqs[[8]])){p <- p+geom_line(aes(x=1:100, y=predict(eqs[[8]], list(x = 1:100))),colour="8")}
#  if(!is.null(eqs[[9]])){p <- p+geom_line(aes(x=1:100, y=predict(eqs[[9]], list(x = 1:100))),colour="9")}
#  if(!is.null(eqs[[10]])){p <- p+geom_line(aes(x=1:100, y=predict(eqs[[10]], list(x = 1:100))),colour="10")}

# p

# r=unlist(strsplit(gsub("\n", "", gsub(" ","",str)),","))
# data=data.frame()
# for(i in 1:length(r)){
# 	y=as.numeric(unlist(strsplit(r[i],"=")))
# 	data=rbind(data,y)
# } 
# names(data) <- c("x", "y")

# fileConn<-file("output.txt")
# writeLines(c("Hello","World"), fileConn)
# close(fileConn)

# counters=list(list())
# count=1
# for (i in 1:length(coun$jobCounters$counterGroup)) {
# 	for (j in 1:length(coun$jobCounters$counterGroup[[i]]$counter)) {
# 		counters[count]=coun$jobCounters$counterGroup[[i]]$counter[[j]] 
# 		print(counters[count])
# 		print("==========")
# 		count=count+1
# 	}
# }

# counters=list()
# count=1
# for (i in 1:length(coun$jobCounters$counterGroup)) {
# 	for (j in 1:length(coun$jobCounters$counterGroup[[i]]$counter)) {
# 		counters[count]=as.data.frame(coun$jobCounters$counterGroup[[i]]$counter[[j]])
# 		print(as.data.frame(coun$jobCounters$counterGroup[[i]]$counter[[j]]))
# 		count=count+1
# 	}
# }
	
# counters=list()
# count=1
# for (i in 1:2) {
# 	for (j in 1:2) {
# 		#counters[count]=as.data.frame(coun$jobCounters$counterGroup[[i]]$counter[[j]])
# 		counters[[count]]=coun$jobCounters$counterGroup[[i]]$counter[[j]]
# 		#print(as.data.frame(coun$jobCounters$counterGroup[[i]]$counter[[j]]))
# 		count=count+1
# 	}
# }
	

# getCounterValue <- function(counters, cname) 
# {
# 	for (i in 1:length(counters)) {
# 		if(counters[[i]]$name== cname){
# 			#return(as.data.frame(counters[[i]]))
# 			return(counters[[i]])
# 		}
# 	}
# }

# ====

#   pushViewport(viewport())
#   grid.text(label = "dharmesh" ,
#     x = unit(1,"npc") - unit(2, "mm"),
#     y = unit(2, "mm"),
#     just = c("right", "bottom"),
#     )
#  popViewport()

#  gt <- ggplot_gtable(ggplot_build(p))
# gt$layout$clip[gt$layout$name=="panel"] <- "off"
# grid.draw(gt)

 

#  grobTree(textGrob("This text stays in place!", x=0.1,  y=0.8, hjust=0,gp=gpar(col="blue", fontsize=12, fontface="italic")))

# my_grob = grobTree(textGrob("This text stays in place!\nThisa more", x=0.1,  y=0.9,gp=gpar(col="blue", fontsize=12, fontface="italic")))
# p+annotation_custom(my_grob)


# my_grob = grobTree(textGrob("This text stays in place!\nThisa more", x=0.1,  y=0.9,gp=gpar(col="blue", fontsize=12, fontface="italic")))

# p+annotation_custom(grobTree(textGrob(q18s2$job$submitTime,x=0.1,y=0.9)))

# p+annotation_custom(grobTree(textGrob(paste("reduceTotal ", q18s2$job$reducesTotal ,"\n","mapsTotal ",q18s2$job$mapsTotal ,"\n","AvgMapTime ",q18s2$job$avgMapTime ,"\n","AvgReduceTime ",q18s2$job$avgReduceTime ,"\n","AvgMergeTime ",q18s2$job$avgMergeTime ,"\n","AvgShuffleTime ",q18s2$job$avgShuffleTime ,"\n"),x=0.1,y=0.8)))



# plotq <- function(RMtimestamp,jobid,numberofjobs=1,title="" , interval=1000, xtick=100, ytick=100){
# 	tasks=data.frame(time=rep(0,1),map=rep(0,1),shuffle=rep(0,1),merge=rep(0,1),reduce=rep(0,1),total=rep(0,1),reduceTasks=rep(0,1),reduceAttempts=rep(0,1))
# 	for (i in seq(jobid, jobid+numberofjobs-1)) {
# 		tmp=getAllCounters(getJob(sprintf("job_%s_%04d",RMtimestamp,i)),interval=interval,count=length(tasks$time))
# 		tasks=rbind(tasks,tmp)
# 	}

# 	ggplot(data=tasks)+theme(legend.title=element_blank()) + scale_x_continuous(breaks = round(seq(0, length(tasks$time), by = xtick),1)) +geom_area(aes(x=time,y=total),fill="darkgrey")+ geom_line(aes(x=time,y=map,colour="map")) +geom_line(aes(x=time,y=shuffle,colour="shuffle")) +geom_line(aes(x=time,y=merge,colour="merge")) +geom_line(aes(x=time,y=reduceTasks,colour="reduceTasks")) +xlab(paste("Time (",interval, " ms)")) + ylab("Number of Tasks")
# }


# myplot <- function(job,title="" , interval=1000, xtick=100, ytick=100){
# 	tasks=getAllCounters(job,interval)
# 	ggplot(data=tasks)+theme(legend.title=element_blank()) + scale_x_continuous(breaks = round(seq(0, length(tasks$time), by = xtick),1)) + scale_y_continuous(breaks = round(seq(0, max(tasks$total)*1.1, by = ytick),1),expand=c(0.1,50)) +geom_area(aes(x=time,y=total),fill="darkgrey")+ geom_line(aes(x=time,y=map,colour="map")) +geom_line(aes(x=time,y=shuffle,colour="shuffle")) +geom_line(aes(x=time,y=merge,colour="merge")) +geom_line(aes(x=time,y=reduceTasks,colour="reduceTasks")) +xlab(paste("Time (",interval, " ms)")) + ylab("Number of Tasks") + ggtitle(paste(title," ",job$job$id)) + annotation_custom(grobTree(textGrob(paste("mapsTotal ",job$job$mapsTotal ," reduceTotal ", job$job$reducesTotal ," AvgMapTime ",job$job$avgMapTime ," AvgReduceTime ",job$job$avgReduceTime ," AvgMergeTime ",job$job$avgMergeTime ," AvgShuffleTime ",job$job$avgShuffleTime),x=0.5,y=0.1)))
# }
 


# myplot <- function(job,title="" , interval=1000, xtick=100, ytick=100){
# 	tasks=getAllCounters(job,interval)
# 	ggplot(data=tasks)+theme(legend.title=element_blank()) + scale_x_continuous(breaks = round(seq(0, length(tasks$time), by = xtick),1), expand=c(0.1,50)) + scale_y_continuous(breaks = round(seq(0, max(tasks$total)*1.1, by = ytick),1)) +geom_area(aes(x=time,y=total),fill="darkgrey")+ geom_line(aes(x=time,y=map,colour="map")) +geom_line(aes(x=time,y=shuffle,colour="shuffle")) +geom_line(aes(x=time,y=merge,colour="merge")) +geom_line(aes(x=time,y=reduceTasks,colour="reduceTasks")) +xlab(paste("Time (",interval, " ms)")) + ylab("Number of Tasks") + ggtitle(paste(title," ",job$job$id)) + annotation_custom(grobTree(textGrob(paste("mapsTotal ",job$job$mapsTotal ,"\n","reduceTotal ", job$job$reducesTotal ,"\n","AvgMapTime ",job$job$avgMapTime ,"\n","AvgReduceTime ",job$job$avgReduceTime ,"\n","AvgMergeTime ",job$job$avgMergeTime ,"\n","AvgShuffleTime ",job$job$avgShuffleTime ,"\n"),x=0.1,y=0.1)))
# }
#  
