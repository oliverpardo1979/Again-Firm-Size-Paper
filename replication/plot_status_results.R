if (.Platform$OS.type == "windows") invisible(Sys.setlocale("LC_CTYPE", "English_United States.utf8"))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
paper <- dirname(dirname(normalizePath(script,winslash="/")))
.libPaths(c(file.path(dirname(paper),"CJC-Monitor/.Rlib"),.libPaths()))
suppressPackageStartupMessages({library(ggplot2);library(dplyr)})
out<-file.path(paper,"replication/status_output")
sizes<-c("Solo","2-3","4-5","6-10","11-19","20-30","31-50","51-100","101+")
c<-read.csv(file.path(out,"contrasts.csv"))
theme_paper<-theme_classic(base_size=14)+theme(legend.position="bottom",strip.background=element_rect(fill="white",color="gray40"),
  strip.text=element_text(face="bold",size=13),axis.text.x=element_text(angle=40,hjust=1),axis.title=element_text(size=14))
palette<-c(Formal="#0072B2",Informal="#D55E00")
save_plot<-function(p,name,height=5)ggsave(file.path(paper,"Paper/figures",paste0(name,"_en.png")),p,width=10,height=height,dpi=300,bg="white")
d<-c %>% filter(model=="M2",clustering=="Sector-department",occupation %in% c(1,4),reference=="Solo") %>%
  mutate(size=factor(size,levels=sizes),formality=factor(formality,levels=c("Formal","Informal")),
    status=factor(occupation,levels=c(1,4),labels=c("Private-sector employees","Own-account workers")))
dodge<-position_dodge(width=.24)
p<-ggplot(d,aes(size,premium,color=formality,shape=formality,group=formality))+
  geom_hline(yintercept=0,linetype="dashed",color="gray50")+
  geom_errorbar(aes(ymin=ci_low,ymax=ci_high),width=.13,alpha=.6,position=dodge)+
  geom_line(linewidth=.65,position=dodge)+geom_point(size=2.3,position=dodge)+facet_wrap(~status,nrow=1)+
  scale_color_manual(values=palette)+scale_shape_manual(values=c(16,17))+
  labs(x="Firm size",y="Premium relative to solo (%)",color=NULL,shape=NULL)+theme_paper
save_plot(p,"status_formality_premiums")
extra<-c %>% filter(model=="M2",clustering=="Sector-department",
  (occupation %in% c(2,5) & reference=="11-19") | (occupation %in% c(3,8) & reference=="Solo"),
  n_origin>=30,n_destination>=30,clusters_origin>=10,clusters_destination>=10) %>%
  mutate(size=factor(size,levels=sizes),formality=factor(formality,levels=c("Formal","Informal")),
    panel=paste0(status,"\nReference: ",reference))
p<-ggplot(extra,aes(size,premium,color=formality,shape=formality,group=formality))+
  geom_hline(yintercept=0,linetype="dashed",color="gray50")+
  geom_errorbar(aes(ymin=ci_low,ymax=ci_high),width=.12,alpha=.6,position=dodge)+geom_line(linewidth=.65,position=dodge)+
  geom_point(size=2.3,position=dodge)+facet_wrap(~panel,ncol=2,scales="free_y")+
  scale_color_manual(values=palette)+scale_shape_manual(values=c(16,17))+
  labs(x="Firm size",y="Premium (%)",color=NULL,shape=NULL)+theme_paper
save_plot(p,"status_other_profiles",8)
# Retain the M0 graph, with a title identifying its restriction rather than calling it preferred.
old<-read.csv(file.path(paper,"replication/preferred_output/profiles.csv")) %>% filter(reference=="Solo") %>%
  mutate(size=factor(size,levels=sizes),group=factor(group,levels=c("Formal","Informal")))
p<-ggplot(old,aes(size,premium))+geom_hline(yintercept=0,linetype="dashed",color="gray50")+
  geom_errorbar(aes(ymin=ci_low,ymax=ci_high),width=.12,color="gray45")+geom_line(aes(group=group),color="#0072B2")+
  geom_point(color="#0072B2",size=2.3)+facet_wrap(~group,nrow=1)+
  labs(x="Firm size",y="Premium relative to solo (%)")+theme_paper
save_plot(p,"status_M0_comparison")
if(file.exists(file.path(out,"annual_profiles.csv"))) {
  annual<-read.csv(file.path(out,"annual_profiles.csv")) %>%
    filter((occupation==1 & reference=="11-19") | (occupation==4 & reference=="Solo"),n_origin>=30,n_destination>=30) %>%
    mutate(status=factor(occupation,levels=c(1,4),labels=c("Private-sector employees","Own-account workers")),
      formality=factor(formal,levels=c(1,0),labels=c("Formal","Informal")),size=factor(size,levels=sizes))
  ep<-annual %>% filter(year %in% c(2008,2025)) %>% mutate(year=factor(year))
  p<-ggplot(ep,aes(size,premium,color=year,shape=year,group=year))+
    geom_hline(yintercept=0,linetype="dashed",color="gray50")+
    geom_errorbar(aes(ymin=ci_low,ymax=ci_high),width=.12,alpha=.6,position=dodge)+
    geom_line(linewidth=.65,position=dodge)+geom_point(size=2.2,position=dodge)+facet_grid(status~formality)+
    scale_color_manual(values=c(`2008`="#D55E00",`2025`="#0072B2"))+scale_shape_manual(values=c(1,16))+
    labs(x="Firm size",y="Firm-size premium (%)",color=NULL,shape=NULL)+theme_paper
  save_plot(p,"status_endpoints",8)
  an<-annual %>% filter(size=="101+") %>% mutate(segment=year>2020)
  p<-ggplot(an,aes(year,premium,group=segment))+
    geom_hline(yintercept=0,linetype="dashed",color="gray50")+
    geom_ribbon(aes(ymin=ci_low,ymax=ci_high),fill="#0072B2",alpha=.15)+geom_line(color="#0072B2",linewidth=.7)+
    geom_point(color="#0072B2",size=2.2)+facet_grid(status~formality)+scale_x_continuous(breaks=c(2008,2013,2019,2025))+
    labs(x="Year",y="101+ premium (%)")+theme_paper+theme(axis.text.x=element_text(angle=0,hjust=.5))
  save_plot(p,"status_dynamics",7.5)
}
