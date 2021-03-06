#######################################################
# check for packages
#######################################################
package.list <- c('vegan','reshape2','dplyr', 'tibble')
for(i in package.list){
  if(!i %in% row.names(installed.packages())) install.packages(i)
}

library(dplyr)

#######################################################
# -- download data off google drive using google-id
#######################################################
data_id_googledrive <- "0B2P104M94skvUmtsZmxUek1lQVk" #simulated data
download.link <- paste0("https://drive.google.com/uc?export=download&id=",data_id_googledrive)
d.in.long <- read.csv(file = download.link, header = T,
                      stringsAsFactors = FALSE)

#######################################################
# -- get community data, make wide
#######################################################
d.comm.long <- subset(d.in.long, OBSERVATION_TYPE == 'TAXON_COUNT')

d.comm.wide <- d.comm.long %>% 
  reshape2::dcast(SITE_ID + DATE ~ VARIABLE_NAME,
                  value.var = 'VALUE',
                  fun.aggregate = mean)

#######################################################
# -- get env data, make wide
#######################################################
d.env.long <- subset(d.in.long, OBSERVATION_TYPE == 'ENV_VAR')

d.env.wide <- d.env.long %>% 
  reshape2::dcast(SITE_ID + DATE ~ VARIABLE_NAME,
                  value.var = 'VALUE',
                  fun.aggregate = mean)

#######################################################
# -- extract spatial coords, make wide
#######################################################
d.space.long <- subset(d.in.long, OBSERVATION_TYPE == 'SPATIAL_COORDINATE')

d.space.wide <- d.space.long %>% 
  reshape2::dcast(SITE_ID ~ VARIABLE_NAME,
                  value.var = 'VALUE',
                  fun.aggregate = mean)

#######################################################
#######################################################
## -- extract 1 time step to test varpart function
######################################################
######################################################

dat.env <- subset(d.env.wide, DATE == 1) %>%
  select(-DATE) %>% 
  data.frame(row.names = NULL) %>% 
  arrange(SITE_ID) %>% 
  na.omit() %>% 
  select(-SITE_ID)

dat.comm <- subset(d.comm.wide, DATE == 1) %>%
  select(-DATE) %>% 
  data.frame(row.names = NULL) %>% 
  arrange(SITE_ID) %>% 
  na.omit()%>% 
  select(-SITE_ID)

dat.space <- d.space.wide %>%
  data.frame(row.names = NULL) %>% 
  arrange(SITE_ID) %>% 
  na.omit()%>% 
  select(-SITE_ID)

##################################################
##################################################
# varpart function based on dbRDA for one timestep
#################################################
##################################################
fn.db.varpart <- function(
  dat.comm,
  dat.env,
  dat.space,
  pre.filter.pval = 0.05, #needed to reduce vars going into model selection if there are too many
  dist.method.choice = 'bray',
  use.all.env.vars = TRUE,
  use.all.space.vars = TRUE,
  ...
){
  
  require(dplyr)
  
  ####################################
  # -- get PCNM vars
  ####################################
  dat.pcnm <- as.data.frame((dat.space %>%
                               dist() %>%
                               vegan::pcnm())$vectors)
  
  
  ####################################
  ####################################
  ####################################
  ####################################
  # If NOT using ALL ENV VARS
  # pre-screen for environmental vars with a pval < user defined cutoff
  # if no variable has a p value better than the cutoff, then we use the one 
  # with the highest R2 value.
  ####################################
  if(!use.all.env.vars){
    E.pvals <- apply(X = dat.env,
                     MARGIN = 2,
                     FUN = function(X){
                       anova(
                         vegan::capscale(
                           vegan::vegdist(dat.comm, method = dist.method.choice) ~ X,
                           na.action = "na.omit",
                           add = TRUE))[1,"Pr(>F)"]
                     }
    )
    
    E.keep <- names(E.pvals[E.pvals < pre.filter.pval])
    
    # calculate adj R2 values for each env var.
    E.R2 <- apply(X = dat.env,
                  MARGIN = 2,
                  FUN = function(X){
                    vegan::RsquareAdj(vegan::capscale(
                      vegan::vegdist(dat.comm, method = dist.method.choice) ~ X,
                      na.action="na.omit",
                      add=TRUE))$adj.r.squared
                  }
    )
  }else{
    E.keep <- names(dat.env)
  }
  
  # -- if no env vars are significant, keep the one with the highest R2 value
  if(!length(E.keep) > 0) E.keep <- names(E.R2[E.R2==max(E.R2)])
  
  dat.env.sig <- data.frame(dat.env[,E.keep])
  names(dat.env.sig) <- E.keep
  
  
  
  #####################################################
  # If NOT using ALL SPATIAL VARS
  # pre-screen for spatial vars with a pval < 0.20
  # if no variable has a p value better than 0.20, then we use the one 
  # with the highest R2 value.
  #####################################################
  if(!use.all.space.vars){
    S.pvals <- apply(X = dat.pcnm,
                     MARGIN = 2,
                     FUN = function(X){
                       anova(
                         vegan::capscale(
                           vegan::vegdist(dat.comm, method = dist.method.choice) ~ X,
                           na.action = "na.omit",
                           add = TRUE))[1,"Pr(>F)"]
                     }
    )
    
    S.keep <- names(S.pvals[S.pvals < pre.filter.pval])
    
    S.R2 <- apply(X = dat.pcnm,
                  MARGIN = 2,
                  FUN = function(X){
                    vegan::RsquareAdj(
                      vegan::capscale(
                        vegan::vegdist(dat.comm, method = dist.method.choice) ~ X,
                        na.action = "na.omit",
                        add = TRUE))$adj.r.squared
                  }
    )
  }else{
    S.keep <- names(dat.pcnm)
  }
    
  if(!length(S.keep) > 0) S.keep <- names(S.R2[S.R2 == max(S.R2)])
  
  dat.pcnm.sig <- data.frame(dat.pcnm[,S.keep])
  names(dat.pcnm.sig) <- S.keep
  
  
  #####################################################
  ############ selecting variables for db RDA models
  #####################################################

  #####################################################
  # -- ENV model selection, if necessary
  #####################################################
  if(use.all.env.vars){
    varselect.env.list <- names(dat.env.sig)
  }else{
    #####################################################
    # -- if NOT using all vars
    # -- Model selection from pre-screened variables using ordiR2step 
    #####################################################
    
    #####################################################
    # -- ENV [E] - select important environmental variables
    #####################################################
    mod0.env <- vegan::capscale(
      vegan::vegdist(dat.comm, method = dist.method.choice) ~ 1, 
      dat.env.sig, 
      na.action = "na.omit",
      add = TRUE) #unconstrained RDA (no predictor variables)
    
    mod1.env <- vegan::capscale(
      vegan::vegdist(dat.comm, method = dist.method.choice) ~ ., 
      dat.env.sig, 
      na.action = "na.omit",
      add = TRUE) #constrained RDA (with all predictor variables) 
    
    mod.step.env <- vegan::ordiR2step(mod0.env,
                                      scope = list(upper = mod1.env,
                                                   lower = mod0.env),
                                      perm.max = 999) #model selection
    
    varselect.env.list <- names(mod.step.env[[7]]$envcentre) #create a list of names of the predictor variables that were significant
    
    if(!length(varselect.env.list) > 0) varselect.env.list<-names(E.R2[E.R2==max(E.R2)]) #if varselect.env.list is empty, keep the var with highest R2
    
    dat.env.sig <- data.frame(dat.env.sig[varselect.env.list]) #keep only the significant predictor variables
  }
  
  #####################################################
  # -- SPATIAL model selection, if necessary
  #####################################################
  if(use.all.space.vars){
    varselect.pcnm.list <- names(dat.pcnm.sig)
  }else{
    #####################################################
    # -- SPATIAL [S] - select important spatial variables
    #####################################################
    mod0.pcnm <- vegan::capscale(
      vegan::vegdist(dat.comm, method = dist.method.choice) ~ 1, 
      dat.pcnm.sig, 
      na.action = "na.omit",
      add = TRUE) #unconstrained RDA (no predictor variables)
    
    mod1.pcnm <- vegan::capscale(
      vegan::vegdist(dat.comm, method = dist.method.choice) ~ ., 
      dat.pcnm.sig, 
      na.action = "na.omit",
      add = TRUE) #constrained RDA (with all predictor variables) 
    
    mod.step.pcnm <- vegan::ordiR2step(mod0.pcnm,
                                       scope = list(upper = mod1.pcnm,
                                                    lower = mod0.pcnm),
                                       perm.max = 999) #model selection
    
    varselect.pcnm.list <- names(mod.step.pcnm[[7]]$envcentre) #create a list of names of the predictor variables that were significant
    
    if(!length(varselect.pcnm.list) > 0) varselect.pcnm.list <- names(S.R2[S.R2==max(S.R2)]) #if varselect.env.list is empty, keep the var with highest R2
    
    dat.pcnm.sig <- data.frame(dat.pcnm.sig[varselect.pcnm.list]) #keep only the significant predictor variables
  }
  
  
  #####################################################
  # -- variaiton paritioning with selected variables
  #####################################################
  #  Note that if no environmetnal variables are siginficant, I think 
  #  use the one with the largest R2. Similarly, I use the PCNM vector
  #  with the largest R2 if none are significant (but two were when I ran the analysis).
  #  as far as I know, we can't use varpart() with capscale, so here's the varpart calcs by hand:
  
  # -- the dbRDA models
  mod.ab <- vegan::capscale(
    vegan::vegdist(dat.comm, method = dist.method.choice) ~ ., 
    dat.env.sig, 
    na.action = "na.omit",
    add = TRUE)
  
  mod.bc <- vegan::capscale(
    vegan::vegdist(dat.comm, method = dist.method.choice) ~ ., 
    dat.pcnm.sig, 
    na.action = "na.omit",
    add = TRUE)
  
  mod.abc <- vegan::capscale(
    vegan::vegdist(dat.comm, method = dist.method.choice) ~ ., 
    cbind(dat.env.sig, dat.pcnm.sig), 
    na.action = "na.omit",
    add = TRUE)
  
  # the dbRDA R2 values
  R2.ab <- vegan::RsquareAdj(mod.ab)$adj.r.squared
  R2.bc <- vegan::RsquareAdj(mod.bc)$adj.r.squared
  R2.abc <- vegan::RsquareAdj(mod.abc)$adj.r.squared
  
  # calculating the varpart components
  R2.a <- R2.abc - R2.bc
  R2.c <- R2.abc - R2.ab
  R2.b <- R2.ab + R2.bc - R2.abc
  R2.d <- 1 - R2.abc
  
  dat.varpart <- data.frame(
    partition = c('[a]',
                  '[b]',
                  '[c]',
                  '[d]',
                  '[a+b]',
                  '[b+c]',
                  '[a+b+c]'),
    notes = c('pure env.',
              'spatially structured env.',
              'pure space',
              'unexplained',
              'total env.',
              'total space',
              'total explained (env. and space)'),
    adj.R2 = c(R2.a,
               R2.b,
               R2.c,
               R2.d,
               R2.ab,
               R2.bc,
               R2.abc),
    P.val = NA,
    Vars = NA,
    Distance.method = dist.method.choice,
    stringsAsFactors = FALSE
  )
  
  
  dat.varpart[5,'Vars']<-paste(names(dat.env.sig),collapse=" + ")
  dat.varpart[5, 'P.val'] <- anova(mod.ab)[1,"Pr(>F)"]
  
  dat.varpart[6,'Vars']<-paste(names(dat.pcnm.sig),collapse=" + ")
  dat.varpart[6, 'P.val'] <- anova(mod.bc)[1,"Pr(>F)"]
  
  dat.varpart[7, 'P.val'] <- anova(mod.abc)[1,"Pr(>F)"]
  
  # -- Conditional dbRDA models to get p values for [a] and [c]
  Y <- vegan::vegdist(dat.comm, method = dist.method.choice)
  X1 <- dat.env.sig
  X2 <- dat.pcnm.sig
  
  # -- pval for [a]
  form.a <- as.formula(
    paste('Y ~ ', 
          paste(names(X1), collapse = ' + '),
          ' + Condition(',
          paste(names(X2), collapse = ' + '),
          ')'))
  
  mod.a <- vegan::capscale(
    form.a,
    data = cbind(X1,X2),
    na.action="na.omit",
    add = TRUE)
  
  dat.varpart[1, 'P.val'] <- anova(mod.a)[1,"Pr(>F)"]
  
  
  # -- pval for [c]
  form.c <- as.formula(
    paste('Y ~ ', 
          paste(names(X2), collapse = ' + '),
          ' + Condition(',
          paste(names(X1), collapse = ' + '),
          ')'))
  
  mod.c <- vegan::capscale(
    form.c,
    data = cbind(X1,X2),
    na.action="na.omit",
    add = TRUE)
  
  dat.varpart[3, 'P.val'] <- anova(mod.c)[1,"Pr(>F)"]
  
  ###################################################
  # Return stats similar to varpart output in vegan
  ###################################################
  return(dat.varpart)
}

####################################
# -- test function on one timestep
####################################

# -- If using sim data, should include 2 env vars and 6 PCNM vars
d.varpart.results <- fn.db.varpart(
  dat.comm,
  dat.env,
  dat.space,
  dist.method.choice = 'horn',
  use.all.env.vars = TRUE,
  use.all.space.vars = TRUE
)

# -- If using sim data, should include 1 env vars and 6 PCNM vars
d.varpart.results <- fn.db.varpart(
  dat.comm,
  dat.env,
  dat.space,
  dist.method.choice = 'horn',
  use.all.env.vars = FALSE,
  use.all.space.vars = TRUE
)

# -- should include 2 env vars and 1 PCNM variable
d.varpart.results <- fn.db.varpart(
  dat.comm,
  dat.env,
  dat.space,
  dist.method.choice = 'horn',
  use.all.env.vars = TRUE,
  use.all.space.vars = FALSE
)

# -- should include 1 env vars and 1 PCNM variable
d.varpart.results <- fn.db.varpart(
  dat.comm,
  dat.env,
  dat.space,
  dist.method.choice = 'horn',
  use.all.env.vars = FALSE,
  use.all.space.vars = FALSE
)





####################################
# -- wrapper function to apply to long-form data, no temporal resolution
####################################
fn.varpart.longform <- function(
  d.in.long,
  select.date = NA,
  ...
){
 
  #######################################################
  # -- get community data, make wide
  #######################################################
  d.comm.long <- subset(d.in.long, OBSERVATION_TYPE == 'TAXON_COUNT')
  
  d.comm.wide <- d.comm.long %>% 
    reshape2::dcast(SITE_ID ~ VARIABLE_NAME,
                    value.var = 'VALUE',
                    fun.aggregate = mean)%>% 
    select(-SITE_ID)
  
  #######################################################
  # -- get env data, make wide
  #######################################################
  d.env.long <- subset(d.in.long, OBSERVATION_TYPE == 'ENV_VAR')
  
  d.env.wide <- d.env.long %>% 
    reshape2::dcast(SITE_ID ~ VARIABLE_NAME,
                    value.var = 'VALUE',
                    fun.aggregate = mean)%>% 
    select(-SITE_ID)
  
  #######################################################
  # -- extract spatial coords
  #######################################################
  d.in.space.long <- subset(d.in.long, OBSERVATION_TYPE == 'SPATIAL_COORDINATE')
  
  d.space.wide <- d.space.long %>% 
    reshape2::dcast(SITE_ID ~ VARIABLE_NAME,
                    value.var = 'VALUE',
                    fun.aggregate = mean)%>% 
    select(-SITE_ID)
  
  #######################################################
  # -- call db varpart function, return results
  #######################################################
  d.varpart.results <- fn.db.varpart(
    dat.comm = d.comm.wide,
    dat.env = d.env.wide,
    dat.space = d.space.wide,
    ...  )
  
  return(d.varpart.results)
}

####################################
# --test wrapper function
####################################
fn.varpart.longform(d.in.long,
                    use.all.env.vars = TRUE,
                    use.all.space.vars = TRUE)

fn.varpart.longform(d.in.long,
                    use.all.env.vars = FALSE,
                    use.all.space.vars = TRUE)

fn.varpart.longform(d.in.long,
                    use.all.env.vars = TRUE,
                    use.all.space.vars = FALSE)

####################################
# -- wrapper function to apply to long-form data, with temporal resolution
####################################

d.in.long
d.in.space.long <- subset(d.in.long, OBSERVATION_TYPE == 'SPATIAL_COORDINATE') %>%
  select(-DATE)
d.space.time.obs.matrix <- d.in.long %>% 
  filter(OBSERVATION_TYPE == 'ENV_VAR') %>%
  select(SITE_ID, DATE)
d.in.space.long.propagated <- full_join(d.space.time.obs.matrix,
                                        d.in.space.long,
                                        by = c('SITE_ID'))
col.name.list <- names(d.in.long)
d.in.long.propagated <- rbind(
  d.in.space.long.propagated[,col.name.list],
  subset(d.in.long, OBSERVATION_TYPE != 'SPATIAL_COORDINATE')[,col.name.list]
)

####################################
# use dplyr::group_by and dplyr::do to apply by date
####################################
d.by.date <- d.in.long.propagated %>% group_by(DATE) 
  
d.varpart.stats.by.time <- do(
  .data = d.by.date, 
  d.stats = fn.varpart.longform(.,
                                use.all.env.vars = TRUE,
                                use.all.space.vars = FALSE))

# returns a list. How shall we format output?

