function [hmmsort] = produceFigures_posthoc(sortfile,varargin)

% load sort file
h = load(sortfile);

% Load user input for params
params = struct('plotFig',1,'saveFig',0,'constrainWindow',[50:150],'discard','auto','merge','auto');
[params,paramsIn] = getOptArgs(varargin,params);

% Set up other plotting parameters
warning('off','stats:pca:ColRankDefX'); % JD: turn off warning about columns of X linearly dependent which pops up in the computeLratio function
params.paperPosition=[0 0 16 12];
params.colors = defineClusterColors;
[params.outputEnding,params.outputOption] = determineFigExportFormat( 'png' );
params.outputpath = [pwd '/FigsVisInsp/'];
% make dir to store the output figures
if exist(params.outputpath,'dir')==7
    rmdir(params.outputpath);
end
mkdir(params.outputpath);
dir = pwd;
pathSessionInd = strfind(dir,'/session');
pathChannelInd = strfind(dir,'/channel');
pathSortThInd = strfind(dir,'/');
params.date = dir(pathSessionInd-8:pathSessionInd-1); % e.g. 20181105
params.channelLong = dir(pathChannelInd+1:pathChannelInd+10); % e.g. channel008
params.channelShort = dir(pathChannelInd+8:pathChannelInd+10); % e.g. 008
params.threshold = dir(pathSortThInd(end)+1:end); % e.g. 0.1
params.label = ['Picasso' params.date params.channelLong ' Th:' dir(pathSortThInd(end)+1:end)];
pathSort = strfind(dir,'/sort');
params.existingFigDir = [dir(1:pathSort-1) '/figs' dir(pathSortThInd(end)+1:end) '/'];


%% Remove any spikes outside of 3 s.d. of each cluster peak amplitude

[h,params] = removeOutlierSpikes(h,params);

%% Remove any spikes that have been assigned to noise cluster

noiseSpikesInd = h.assignedNegative == params.noiseClusterInd;

h.newSpikesNegative(noiseSpikesInd,:) = [];
h.newTimestampsNegative(noiseSpikesInd) = [];
h.allSpikesCorrFree(noiseSpikesInd,:) = [];
h.allSpikeInds(noiseSpikesInd) = [];
h.assignedNegative(noiseSpikesInd) = [];

%% Plot single cluster figures (a la oSort) - raw waveforms, ISI, etc
% From produceFigures.m / plotSingleCluster.m

% order of clusters - largest first
clusters = flipud(h.useNegative);
h.clustersOrig = clusters;

plotsinglecluster(h,params,clusters);

%% Plots and exports projection test figures
% From produceProjectionFigures.m

if params.saveFig
    mode = 1;
else 
    mode = 3;
end
[d] = projectiontest(h,params,clusters,mode);

%% Calculate L ratio and Isolation distance
% From computeLratioALLclusters.m

version = 3; % Version 3 uses 1st 3 PCA components and peak amp
[L,L_R,IsolDist,features] = clusterquality(h,params,clusters,version);
h.L = L';
h.L_R = L_R';
h.IsolDist = IsolDist';
h.features = features;

%% Plot PCA figure  

figure(123);
plotpcafig(h,params,clusters);
close(gcf);

%% Find clusters to discard
% Plot raw waveforms of each cluster, as well as several example raw traces
% with spikes indicated
% Get user input on whether to accept or reject (with user input on what to discard instead) suggested discards

% Discard clusters
[h,params] = discardclusters(h,params,clusters);
if isempty(h.clustersPostDiscard)
    disp('No clusters found');
    return;
end

% Reduce the projection test matrix to remaining clusters
d = d( (ismember(d(:,1),h.clustersPostDiscard) & ismember(d(:,2),h.clustersPostDiscard)),:);
h.dPostDiscard = d;

%% Suggest merging of clusters
      
[mergeSuggestion,clustersCurrent] = suggestMerge(h,params,d);

[h,mergeSuggestion,clustersCurrent,d] = mergeclusters(h,params,mergeSuggestion,clustersCurrent,d);
h.dPostMerge = d;
h.mergeSuggestion = mergeSuggestion;
h.clustersCurrent = clustersCurrent;

%% Save merged file

sortfileshort = sortfile(1:strfind(sortfile,'.mat')-1);
mergedfilename = horzcat(sortfileshort, '_merged', '.mat');
if exist(mergedfilename,'file') ==2
    delete(mergedfilename);
end
save(mergedfilename,'-v7.3','-struct','h');

%% Put osort structure into hmmsort structure

[hmmsort] = splitsortintocells(mergedfilename);







    
    
    
    
    
    
    
    
    
    
    


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



function [h,params] = removeOutlierSpikes(h,params)

%%% Remove any spikes outside of 3 s.d. of each cluster's mean peak amplitude

% Define noise cluster
defineSortingConstants;
params.noiseClusterInd = CLUSTERID_NOISE_CLUSTER;
% Retrieve variables
nrAssigned = h.nrAssigned;
newSpikesNegative = h.newSpikesNegative;
assignedNegative = h.assignedNegative;
useNegative = h.useNegative;

for ii = 1:size(h.nrAssigned,1)
    
    % Find those spikes of each cluster that have peak amps  within/outside 3 s.d. of cluster
    zscoreInds = find(assignedNegative' == nrAssigned(ii,1));
    zscorePeaks = zscore(newSpikesNegative(zscoreInds,95),0,1);
    exceed3sdInds = zscoreInds(abs(zscorePeaks)>3);
    within3sdInds = setdiff(zscoreInds,exceed3sdInds);
    
    if isempty(exceed3sdInds)
        continue;
    end
    
    % Adjust output variables
    if length(within3sdInds)<100 % If any cluster now contain fewer than 100 spikes, remove that clusters
        assignedNegative(:,zscoreInds') = CLUSTERID_NOISE_CLUSTER;
        nrAssigned(ii,:) = [];
        useNegative(useNegative(1,:)==nrAssigned(ii,1),:) = [];
    else % Assign the spikes that exceed 3 s.d. to noise cluster
        assignedNegative(:,exceed3sdInds') = CLUSTERID_NOISE_CLUSTER;
        nrAssigned(ii,2) = length(within3sdInds);
    end
end

% Re-sort order of clusters according to number of spikes - smallest first
nrAssigned = sortrows(nrAssigned,2);
useNegative = nrAssigned(:,1);
% Assign to output
h.nrAssigned = nrAssigned;
h.assignedNegative = assignedNegative;
h.useNegative = useNegative;
params.spikeLength = size(newSpikesNegative,2);

function [] = plotsinglecluster(h,params,clusters)

%%% Plot single cluster figures (a la oSort) - raw waveforms, ISI, etc
%%% From produceFigures.m

newSpikesNegative = h.newSpikesNegative;
assignedNegative = h.assignedNegative;
newTimestampsNegative = h.newTimestampsNegative;

figure(123);
set(gcf,'visible','off');
close(gcf);
switch params.saveFig
    case 1
        for i=1:length(clusters)
            cluNr=clusters(i);
            if sum(assignedNegative == cluNr)==0
                continue;
            end
            disp(['Figure for cluster nr ' num2str(cluNr)]);

            figh = figure(cluNr);
            set(gcf,'visible','off');

            %try 
            plotSingleCluster(newSpikesNegative, newTimestampsNegative, assignedNegative, [params.label '(-)'],  cluNr, params.colors{i},[]); 

            %end
            scaleFigure;
            set(gcf,'PaperUnits','inches','PaperPosition',params.paperPosition)

            fNameOutpng = [params.outputpath 'P' params.channelLong '_CL_' num2str(cluNr) '_THM_' params.outputEnding  ];
            fNameOutfig = [params.outputpath 'P' params.channelLong '_CL_' num2str(cluNr) '_THM_' '.fig'  ];
            disp(['Writing:' fNameOutpng]);

            print(gcf,params.outputOption, fNameOutpng);
            savefig(figh,fNameOutfig);

            close(gcf);
        end

        disp(['figure sorting result all']);

        figure(888);
        set(gcf,'visible','off');
        close(gcf);   % make sure its closed if it already exists
        figh = figure(888);
        set(gcf,'visible','off');

        plotSortingResultRaw(newSpikesNegative, [], assignedNegative, [], clusters, [], [params.label '(-)'], params.colors )    
        scaleFigure;
        set(gcf,'PaperUnits','inches','PaperPosition',params.paperPosition)

        fNameOutpng = [params.outputpath 'P' params.channelLong '_CL_ALL' '_THM_' params.outputEnding];
        fNameOutfig = [params.outputpath 'P' params.channelLong '_CL_ALL' '_THM_' 'fig'];
        disp(['Writing:' fNameOutpng]);

        print(gcf,params.outputOption, fNameOutpng);
        savefig(figh,fNameOutfig);
        close(gcf);

        if length(clusters)==0
            return;
        end
end

function [] = plotpcafig(h,params,clusters,clusterHighlightInd)

%%% Plot PCA figure 
%%%
%%% (Inputs)
%%%     Mode -              1: Plot PC1 against PC2 (in a new figure window)
%%%                         2: Plot PC1 against peak amp (in whichever axis currently active)
%%%
%%%     params.plotFig -    1: plots figures in real time (not saved)
%%%                         0: Does not plot

assignedNegative = h.assignedNegative;
allSpikesCorrFree = h.allSpikesCorrFree;
features = h.features;

switch params.plotFig
    case 1 % Plot figures in real time

        plotInds=[];
        allInds=[];
        for i=1:length(clusters)
            cluNr=clusters(i);
            plotInds{i} = find( assignedNegative == cluNr );
            allInds=[allInds plotInds{i}];
        end
        noiseInds=setdiff(1:length(assignedNegative),allInds);

        plot( features(noiseInds,1), features(noiseInds,2), '.', 'color', [0.5 0.5 0.5]);
        hold on
        for i=1:size(clusters,1)
            plot( features(plotInds{i},1), features(plotInds{i},2), '.', 'color', params.colors{clusters(i)==h.clustersOrig});
        end
        if nargin > 3 % If need to highlight a specific cluster
            plot( features(plotInds{clusterHighlightInd},1), features(plotInds{clusterHighlightInd},2), '.', 'color', params.colors{clusters(clusterHighlightInd)==h.clustersOrig});
        end
        hold off

        %focus on the data,not the noise; check if first argument<second to avoid
        %weird xlim/ylim errors if not ordered (negative numbers)
        if abs(min(features(allInds,1))) < abs(max(features(allInds,1)))
            xlims=[ 0.9*min(features(allInds,1)) 1.1*max(features(allInds,1))];
        else
            xlims=[ 1.1*min(features(allInds,1)) 0.9*max(features(allInds,1)) ];
        end
        if xlims(1)<xlims(2)
            xlim(xlims);
        end
        if abs(min(features(allInds,2))) < abs(max(features(allInds,2)))
            ylims=[ 0.9*min(features(allInds,2)) 1.1*max(features(allInds,2))];
        else
            ylims=[ 1.1*min(features(allInds,2)) 0.9*max(features(allInds,2))];
        end
        if ylims(1)<ylims(2)
            ylim(ylims);
        end

        stdWaveforms=mean(std(allSpikesCorrFree));
        title(['feature1/feature2, whitened std=' num2str(stdWaveforms)]);
        scaleFigure;
        set(gcf,'PaperUnits','inches','PaperPosition',params.paperPosition)
        if params.saveFig
            print(gcf, params.outputOption, [params.outputpath 'P' params.channelLong '_PCAALL_THM_' params.outputEnding ]);
            close(gcf);
        end

               
end

function [d] = projectiontest(h,params,clusters,mode)

%%% From produceProjectionFigures.m
%%% 
%%% Inputs:
%%%     Mode -      1: Plot in real time and save figures
%%%                 3: Plot in real time but doesn't save

newSpikesNegative = h.newSpikesNegative;
allSpikesCorrFree = h.allSpikesCorrFree;
assignedNegative = h.assignedNegative;

%--- significance test between all clusters
pairs=[];
pairsColor=[];
c=0;
for i=1:size(clusters,1)
    for j=i+1:(size(clusters,1))
        c=c+1;
        pairs(c,1:2)=[clusters(i) clusters(j)];
        pairsColor(c,1:2)=[i j];
    end
end
rawWaveformsConstrained = newSpikesNegative(:,params.constrainWindow);
allSpikesCorrFreeConstrained = allSpikesCorrFree(:,params.constrainWindow);
d = [];
if params.saveFig % Plots and saves projection test figures
    for i=1:size(pairs,1)
        figure(123)
        set(gcf,'visible','off');
        disp(['figure cluster pair ' num2str(i) ' ' num2str(pairs(i,:))]);
        d(i) = figureClusterOverlap(allSpikesCorrFreeConstrained,rawWaveformsConstrained,assignedNegative,pairs(i,1),pairs(i,2),params.label,mode,{params.colors{pairsColor(i,1)},params.colors{pairsColor(i,2)}} );
        scaleFigure;
        set(gcf,'PaperUnits','inches','PaperPosition',params.paperPosition)
        print(gcf, params.outputOption, [params.outputpath 'P' params.channelLong '_SepTest_' num2str(pairs(i,1)) '_' num2str(pairs(i,2)) '_THM_' params.outputEnding ]);
        close(gcf);
    end

    %if there is only one: print distribution in any case
    if size(pairs,1)==0 && length(clusters)==1
        figure(123);
        set(gcf,'visible','off');
        d = figureClusterOverlap(allSpikesCorrFreeConstrained,rawWaveformsConstrained,assignedNegative,clusters(1),0,params.label,mode,{params.colors{1},params.colors{2}} );
        scaleFigure;
        set(gcf,'PaperUnits','inches','PaperPosition',params.paperPosition)
        print(gcf, params.outputOption, [params.outputpath 'P' params.channelLong '_SepTest_' num2str(clusters(1)) '_' num2str(clusters(1)) '_THM_' params.outputEnding ]);
        close(gcf);
    end
else
    for i=1:size(pairs,1)
        d(i) = figureClusterOverlap(allSpikesCorrFreeConstrained,rawWaveformsConstrained,assignedNegative,pairs(i,1),pairs(i,2),params.label,mode,{params.colors{pairsColor(i,1)},params.colors{pairsColor(i,2)}} );
    end

    %if there is only one: print distribution in any case
    if size(pairs,1)==0 && length(clusters)==1
        d = figureClusterOverlap(allSpikesCorrFreeConstrained,rawWaveformsConstrained,assignedNegative,clusters(1),0,params.label,mode,{params.colors{1},params.colors{2}} );
    end
end
% Append identity of clusters used to calculate projection distance
d = [pairs d'];

function [L,L_R,IsolDist,features] = clusterquality(h,params,clusters,version)

%%% Get L ratio and Isolation Distance for each cluster
%%% From computeLratioALLclusters.m

newSpikesNegative = h.newSpikesNegative;
assignedNegative = h.assignedNegative;

% Restrict spikes to non-noise clusters only (non-99999999) %%%%%%%%%%%%%%%
% ????????????????????????##################################!!!!!!!!!!!!!!
% assignedNegative = assignedNegative(assignedNegative ~= params.noiseClusterInd);
% newSpikesNegative = newSpikesNegative(assignedNegative ~= params.noiseClusterInd,:);

switch(version)
    case 1
        [pc,score,latent,tsquare] = pca(newSpikesNegative);
        score=score(:,1:3); %first three PCs
        
        features=score;
    case 2
        %energy of each
        [E,peakAmp,area]=getWaveformEnergy( newSpikesNegative,params.constrainWindow);
        E2=repmat(E,size(newSpikesNegative,2),1)';
        %normalize each waveform by its energy
        waveforms_normalized=[];
        
        waveforms_normalized=newSpikesNegative./E2;

        [pc,score,latent,tsquare] = pca( waveforms_normalized );
 
        
        features(:,1)=score(:,1);  % first PC
        features(:,2)=E;
        features(:,3)=peakAmp;
        features(:,4)=area;
        
        features(:,5)=score(:,2);  %  PC
        features(:,6)=score(:,3);  %  PC
        features(:,7)=score(:,4);  %  PC
        features(:,8)=score(:,5);  %  PC
        
    case 3 % HM Edit - use Redish original suggested features
        
        %energy of each
        [E,peakAmp,area]=getWaveformEnergy( newSpikesNegative,params.constrainWindow);
        E2=repmat(E,size(newSpikesNegative,2),1)';
        %normalize each waveform by its energy
        waveforms_normalized=[];
        
        waveforms_normalized=newSpikesNegative./E2;

        [pc,score,latent,tsquare] = pca( waveforms_normalized );
        
        features(:,1) = score(:,1);
        features(:,2) = peakAmp;
        features(:,3) = score(:,2);
        features(:,4) = score(:,3);
        
        
    otherwise
        error('unknown version')
end

for ii=1:length(clusters)
    
    idx=find(assignedNegative==clusters(ii));
    if size(features,2)>size(features,1) || size(features,2)>length(idx)
        %cant compute if more features than spikes are in this cluster
        L(ii)=nan;
        L_R(ii)=nan;
        IsolDist(ii)=nan;
    else
        [L(ii),L_R(ii)]=L_Ratio( features,idx); %Mclust function
        IsolDist(ii) = IsolationDistance(features, idx);
    end
end

function [E,peakAmp,area] = getWaveformEnergy( waveforms,constrainWindow)
E=[];
peakAmp=[];
area=[];
dOfUnits=[];
% N=size(waveforms,2);  % nr datapoints per waveform
N = length(constrainWindow); % HM Edit
for j=1:size(waveforms,1)
    E(j) = sqrt(sum(waveforms(j,constrainWindow).^2)/N);
    
%     [~,Im]=max(abs(waveforms(j,:)));
    Im = 95; % HM Edit - peak amp is at 95th point
    
    peakAmp(j) = waveforms(j,Im);  % amplitude of peak, regardless of positive/negative
    area(j) = sum(abs(waveforms(j,:)));
    
end

function [h,params] = discardclusters(h,params,clusters)

%%% Based on automatic or user selection, discard noise clusters
%%%
%%% Input:
%%%     params.discard -    'auto': automatic selection, based on waveform
%%%                                 width (mean of cluster), L ratio, IsoD
%%%                         'choose': user review, after initial auto
%%%                                 selection

newSpikesNegative = h.newSpikesNegative;
assignedNegative = h.assignedNegative;
nrAssigned = h.nrAssigned;
L_R = h.L_R;
IsolDist = h.IsolDist;

finishDiscard = false;
while ~finishDiscard

    % Auto-select clusters to discard based on mean cluster waveform width
    [discardInd,meanWaveform,width] = selectDiscard(h,clusters,L_R,IsolDist); % ordered according to variable 'clusters' (largest first)
    
    % Plot each cluster for making decision to discard/keep
    params.yAxisLim = [min(meanWaveform(:))-25 max(meanWaveform(:))+25];
    if strcmp(params.discard,'choose')

        for ii = 1:size(clusters,1)
            % Set up figure
            hfig = figure(clusters(ii));
            set(hfig,'Units','Normalized','OuterPosition',[0 0 1 1]);
            hold on
            % Retrieve existing raw trace figure with spike overlay
            sh1 = subplot(2,2,[1 3]);
            image(sh1,imread([params.existingFigDir 'P1' '_CL_' num2str(clusters(ii)) '_zRAW1' params.outputEnding]));
            set(sh1,'XTickLabel',{},'YTickLabel',{});  
            if discardInd(ii)
                status = 'Discard';
            else
                status = 'Keep';
            end
            title([status,': ','Waveform width = ',num2str(width(ii)),', ','IsoD = ',num2str(IsolDist(ii)),', ','L Ratio = ',num2str(L_R(ii))]); 
            % Plot raw waveforms
            sh2 = subplot(2,2,2);
            spikesToDraw = newSpikesNegative( find(assignedNegative==clusters(ii)),:);
            plotrawwaveforms(sh2,spikesToDraw,clusters,clusters(ii),params);
            title(['Cluster ' num2str(clusters(ii)) ' (' num2str(ii) 'of ' num2str(size(clusters,1)) ' clusters)']);
            
            % Plot first PC against peak amplitude
            sh3 = subplot(2,2,4);
            hold(sh3,'on');
            plotpcafig(h,params,clusters,ii);
            % Re-size
            set(sh1,'Position',[0.05 0.1 0.6 0.8]);
            set(sh2,'Position',[0.7 0.6 0.25 0.3]);
            set(sh3,'Position',[0.7 0.1 0.25 0.3]);
            hold off

            % Let user decide whether to keep or discard
            uicontrol(hfig,'String','Ready to decide','Units','Normalized','Position',[0.85 0.45 0.1 0.1],'Callback','uiresume');
            uiwait(hfig);
            discard_review = questdlg('Keep or discard?','Decide','Keep','Discard',status);
            if isempty(discard_review)
                error('You did not decide whether to keep or discard the cluster');
            end
            switch discard_review
                case 'Keep'
                    discardInd(ii) = false; % Set to keep
                case 'Discard'
                    discardInd(ii) = true; % Set to discard
            end
            close(hfig);
        end
    end
    finishDiscard = true;

end

% Update variables
assignedNegative(ismember(assignedNegative,clusters(discardInd))) = 99999999;
nrAssigned = nrAssigned(flipud(~discardInd),:);
nrAssigned = sortrows(nrAssigned,2);
useNegative = nrAssigned(:,1);

% Replace output structure
h.clustersPostDiscard = clusters(~discardInd);
h.clustersDiscarded = clusters(discardInd);
h.assignedNegativePostDiscard = assignedNegative;
h.nrAssignedPostDiscard = nrAssigned;
h.useNegativePostDiscard = useNegative;
h.width = [clusters width];

function [discardInd,meanWaveform,width] = selectDiscard(h,clusters,L_R,IsolDist,selection)
% Identify 
% 1. oscillatory noise clusters to discard based on waveform width > 50 (pre-peak to peak)
% 2. Poorly isolated clusters that have L ratio > 0.2, Isolation distance < 15 (See Anikeenvca Deisseroth 2012 Nat Neurosci)

newSpikesNegative = h.newSpikesNegative;
assignedNegative = h.assignedNegative;

if nargin>4
    discardInd = ismember(clusters,selection);
else
    
    meanWaveform = nan(size(clusters,1),size(newSpikesNegative,2));
    width = nan(size(clusters,1),1);
    for ii = 1:size(clusters,1)
        % Get mean waveform
        meanWaveform(ii,:) = mean(newSpikesNegative(assignedNegative==clusters(ii),:),1);
        % Find waveform width
        if meanWaveform(ii,95) > 0 % If positive peak, find local min before peak
            [~,localpeakInd] = findpeaks(-meanWaveform(ii,:));
        elseif meanWaveform(ii,95) < 0 % If negative peak, find local max before peak
            [~,localpeakInd] = findpeaks(meanWaveform(ii,:));
        end
        localpeakInd = localpeakInd(find(localpeakInd<95,1,'last'));
        if ~isempty(localpeakInd)
            width(ii) = 95-localpeakInd;
        else
            width(ii) = 95; % When there is no pre-peak local max/min
        end
    end
%     discardInd = width>50 | L_R>0.2 | IsolDist<15; % See Anikeenvca Deisseroth 2012 Nat Neurosci
    discardInd = width>50;
end

function [mergeSuggestion,clustersCurrent] = suggestMerge(h,params,d)

% Use cluster projection tests to suggest merges
MergeOrNot = true;
useNegative = h.useNegativePostDiscard;
nrAssigned = h.nrAssignedPostDiscard;
assignedNegative = h.assignedNegativePostDiscard;
% newSpikesNegative = h.newSpikesNegative;
clustersCurrent = h.clustersPostDiscard;
dToInspect = d;
mergeSuggestion = {};
% Merge recursively, starting from largest cluster
while MergeOrNot
    % Sort to start merging with smallest d
    dToInspect = sortrows(dToInspect,3);
    clustersToMerge = dToInspect(dToInspect(:,3)<5,1:2);
    if isempty(clustersToMerge)
        break;
    end
    clust1st = clustersToMerge(1,1);
    clust2nd = clustersToMerge(1,2);
    if ismember(clust2nd,useNegative) % If to-be-merged cluster has already been merged into a bigger cluster in previous iteration, skip
        % Put spikes of to-be-merged cluster into 1st cluster
        assignedNegative(assignedNegative(1,:)==clust2nd) = clust1st;
        nrAssigned(nrAssigned(:,1)==clust1st,2) = sum(assignedNegative(1,:)==clust1st);
        nrAssigned(nrAssigned(:,1)==clust2nd,:) = [];
        % Re-sort clusters by size, flip to look at biggest cluster first
        nrAssigned = sortrows(nrAssigned,2);
        useNegative = nrAssigned(:,1);
        clustersCurrent = flipud(nrAssigned(:,1));
    end
    % Collect merge suggestions
    if isempty(mergeSuggestion)
        mergeSuggestion{1,1} = clust1st;
        mergeSuggestion{1,2} = clust2nd;
    else
        % If 2nd cluster already has other clusters merged into it 
        full2nd = ismember(cell2mat(mergeSuggestion(:,1)),clust2nd);
        if any(full2nd)
            mergeSuggestion{full2nd,2} = [clust2nd mergeSuggestion{full2nd,2}];
            mergeSuggestion{full2nd,1} = clust1st;
            double1st = find(ismember(cell2mat(mergeSuggestion(:,1)),clust1st));
            if length(double1st)>1
                mergeSuggestion{double1st(1),2} = [mergeSuggestion{double1st(1),2} mergeSuggestion{double1st(2),2}];
                mergeSuggestion(double1st(2),:) = [];
            end
        else % If 2nd cluster is free of previous merges
            existingMerge = ismember(cell2mat(mergeSuggestion(:,1)),clust1st);
            if any(existingMerge) % If 1st cluster already has merges
                mergeSuggestion{existingMerge,2} = [mergeSuggestion{existingMerge,2} clust2nd];
            else % If neither 1st or 2nd cluster have previously been merged
                mergeSuggestion{end+1,1} = clust1st;
                mergeSuggestion{end,2} = clust2nd;
            end
        end
    end
    % Save in temporary h structure
    htemp = h;
    htemp.nrAssigned = nrAssigned;
    htemp.useNegative = useNegative;
    htemp.assignedNegative = assignedNegative;
    % Redo projection test
    if params.saveFig
        mode = 1;
    else 
        mode = 3;
    end
    [dToInspect] = projectiontest(htemp,params,clustersCurrent,mode);
    if isnan(dToInspect) % If all other clusters have been merged into 1
        break;
    end
    
end

function [h,mergeSuggestion,clustersCurrent,d] = mergeclusters(h,params,mergeSuggestion,clustersCurrent,d)

newSpikesNegative = h.newSpikesNegative;
assignedNegative = h.assignedNegativePostDiscard;
clustersOrig = h.clustersOrig;
nrAssigned = h.nrAssignedPostDiscard;
mergeSuggestionOrig = mergeSuggestion;
useNegative = h.useNegativePostDiscard;

% Plot PCA component 1 & 2
figure(123);
plotpcafig(h,params,clustersCurrent);

discardClusters = [];
switch params.merge
    case 'choose'
        happyWithMerge = false;
        while ~happyWithMerge
            
            % Plot for inspection
            hfig = figure('Units','Normalized','OuterPosition',[0 0 1 1]);
            hold on
            if isempty(mergeSuggestion) % If nothing to merge

                % Plot all clusters separately
                for ii = 1:size(clustersCurrent,1)
                    % Plot raw waveforms
                    sh1 = subplot(2,size(clustersCurrent,1),ii);
                    spikesToDraw = newSpikesNegative( find(assignedNegative==clustersCurrent(ii)),:);
                    plotrawwaveforms(sh1,spikesToDraw,clustersOrig,clustersCurrent(ii),params)
                    if ismember(clustersCurrent(ii),discardClusters)
                        title(['Discard: Cluster ' num2str(clustersCurrent(ii))]);
                    end
                end
                hold off

            else % If there are merge suggestions

                % Plot clusters with their merging suggestions
                maxsubplot = 2+max(cellfun(@length,mergeSuggestion(:,2)));
                for ii = 1:size(clustersCurrent,1)

                    % Plot raw waveforms for main cluster
                    sh1 = subplot(maxsubplot,size(clustersCurrent,1),ii);
                    spikesToDrawMain = newSpikesNegative( find(assignedNegative==clustersCurrent(ii)),:);
                    plotrawwaveforms(sh1,spikesToDrawMain,clustersOrig,clustersCurrent(ii),params);
                    if ismember(clustersCurrent(ii),discardClusters)
                        title(['Discard: Cluster' num2str(clustersCurrent(ii))]);
                    end

                    % Plot raw waveforms for clusters to be merged in
                    if any(ismember(cell2mat(mergeSuggestion(:,1)),clustersCurrent(ii)))

                        row = ismember(cell2mat(mergeSuggestion(:,1)),clustersCurrent(ii));
                        toMerge = mergeSuggestion{row,2};
                        % Plot original cluster into overlay window
                        soverlay = subplot(maxsubplot,size(clustersCurrent,1),ii+(size(toMerge,2)+1)*size(clustersCurrent,1));
                        plotrawwaveforms(soverlay,spikesToDrawMain,clustersOrig,clustersCurrent(ii),params);

                        % Plot separately each individual cluster that is to be merged in
                        spikesToDrawMergedMean = nan(size(toMerge,1),size(newSpikesNegative,2));
                        for jj = 1:size(toMerge,2)
                            dvalue = d( (d(:,1)==clustersCurrent(ii) & d(:,2)==toMerge(jj) | d(:,2)==clustersCurrent(ii) & d(:,1)==toMerge(jj)),3);
                            % Plot separately
                            sh1 = subplot(maxsubplot,size(clustersCurrent,1),ii+jj*size(clustersCurrent,1));
                            spikesToDraw = newSpikesNegative( find(assignedNegative==toMerge(jj)),:);
                            spikesToDrawMergedMean(jj,:) = mean(spikesToDraw);
                            plotrawwaveforms(sh1,spikesToDraw,clustersOrig,toMerge(jj),params);
                            title(['Cluster ' num2str(toMerge(jj)),': d = ',num2str(dvalue)]);
                            % Plot into overlay window
                            axes(soverlay);
                            plotrawwaveforms(soverlay,spikesToDraw,clustersOrig,toMerge(jj),params);
                        end
                        axes(soverlay);
                        hold(soverlay,'on')
                        for jj = 1:size(toMerge,2)
                            % Make sure line for average waveform is in a different color
                            avColor='w';
                            plot(1:params.spikeLength, spikesToDrawMergedMean(jj,:),avColor, 'linewidth', 2);
                        end
                        % Make sure line for average waveform is in a different color
                        avColor='k';
                        plot(1:params.spikeLength, mean(spikesToDrawMain),avColor, 'linewidth', 2);
                        title(['Cluster ',num2str(clustersCurrent(ii)),' ',num2str(toMerge)]);
                        hold(soverlay,'off')
                    end
                end

            end
            % Add user input for merging suggestions
            uicontrol(hfig,'String','Decide','Units','Normalized','Position',[0.85 0.1 0.1 0.1],'Callback','uiresume');
            uiwait(hfig);
            merge_review = questdlg('Happy with the suggested merge?','Happy?','Yes','No','Reset','Yes');
            if isempty(merge_review)
                error('You did not decide whether you were happy with the suggested merge');
            end
            switch merge_review
                case 'No'
                    % Ask for user input for alternative merge
                    clusterNames = {};
                    for kk = 1:size(h.clustersPostDiscard,1)
                        clusterNames{kk} = horzcat('Cluster ',num2str(h.clustersPostDiscard(kk)));
                    end
                    userMergeSuggestions = inputdlg(clusterNames,'Group the clusters as you see fit');
                    userMergeSuggestions = str2double(userMergeSuggestions);

                    close(hfig);
                    
                    % Pick out ones to discard
                    if any(isnan(userMergeSuggestions))
                        discardClusters = h.clustersPostDiscard(isnan(userMergeSuggestions));
                    else 
                        discardClusters = [];
                    end
                    mergeSuggestion = {};
                    uniqueUserMergeSuggestions = unique(userMergeSuggestions);
                    uniqueUserMergeSuggestions = uniqueUserMergeSuggestions(~isnan(uniqueUserMergeSuggestions));
                    % Collate rest of user input for clusters to merge
                    for ii = 1:size(uniqueUserMergeSuggestions,1)
                        if sum(userMergeSuggestions==uniqueUserMergeSuggestions(ii))>1 % If there are any to be merged
                            clust = h.clustersPostDiscard(userMergeSuggestions==uniqueUserMergeSuggestions(ii));
                            if isempty(mergeSuggestion)
                                mergeSuggestion{1,1} = clust(1);
                                mergeSuggestion{1,2} = clust(2:end)';
                            else
                                mergeSuggestion{end+1,1} = clust(1);
                                mergeSuggestion{end,2} = clust(2:end)';
                            end
                        end
                    end
                    % Update clustersCurrent 
                    if ~isempty(mergeSuggestion)
                        clustersCurrent = setdiff(h.clustersPostDiscard,cell2mat(mergeSuggestion(:,2)'));
                        % Sort according to size
                        clustersCurrent = flipud(h.nrAssigned(ismember(h.nrAssigned(:,1),clustersCurrent),1));
                    else
                        clustersCurrent = h.clustersPostDiscard;
                    end
                case 'Yes' % Exit with the current merge suggestions
                    happyWithMerge = true; % Set to discard
                    close(hfig);
                    close(figure(123));
                case 'Reset' % Reset to the automatic merge suggestions
                    mergeSuggestion = mergeSuggestionOrig;
                    % Update clustersCurrent 
                    if ~isempty(mergeSuggestion)
                        clustersCurrent = setdiff(h.clustersPostDiscard,cell2mat(mergeSuggestion(:,2)'));
                        % Sort according to size
                        clustersCurrent = flipud(h.nrAssigned(ismember(h.nrAssigned(:,1),clustersCurrent),1));
                    else
                        clustersCurrent = h.clustersPostDiscard;
                    end
                    discardClusters = [];
                    close(hfig);
            end

        end
end

% Update output variables
if ~isempty(discardClusters)
    for ii = 1:size(discardClusters,1)
        assignedNegative(assignedNegative == discardClusters(ii)) = params.noiseClusterInd;
        nrAssigned(nrAssigned(:,1) == discardClusters(ii),:) = [];
        h.clustersDiscarded = [h.clustersDiscarded;discardClusters(ii)];
    end
    % Re-order according to cluster size
    nrAssigned = sortrows(nrAssigned,2);
    useNegative = nrAssigned(:,1);
    h.clustersPostDiscard = flipud(useNegative);
end
for ii = 1:size(mergeSuggestion,1)
    clust1st = mergeSuggestion{ii,1};
    clust2nd = mergeSuggestion{ii,2};
    for jj = 1:size(clust2nd,2)
        assignedNegative(assignedNegative == clust2nd(jj)) = clust1st;
        nrAssigned(nrAssigned(:,1) == clust1st,2) = sum(assignedNegative == clust1st);
        nrAssigned(nrAssigned(:,1) == clust2nd(jj),:) = [];
        % Re-order according to cluster size
        nrAssigned = sortrows(nrAssigned,2);
        useNegative = nrAssigned(:,1);
        clustersCurrent = flipud(useNegative);
    end
end
h.assignedNegativePostMerge = assignedNegative;
h.nrAssignedPostMerge = nrAssigned;
h.useNegativePostMerge = useNegative;
% Redo projection test for saving
if params.saveFig
    mode = 1;
else 
    mode = 3;
end
[d] = projectiontest(h,params,clustersCurrent,mode);

function [] = plotrawwaveforms(handle,spikesToDraw,clustersOrig,thiscluster,params,spikeColor)

% Plots only 10000 of spikes if number of spikes > 10000
% This is because plotting too many spikes slows Matlab down significantly
% to the point of hanging

if nargin<6
    spikeColor = params.colors{thiscluster==clustersOrig};
end
% Subsample if there are too many spikes (too many spikes slows Matlab down
% significantly to the point of hanging)
if size(spikesToDraw,1)>5000
    spikesToDrawSubset = datasample(spikesToDraw,5000,1,'Replace',false);
else
    spikesToDrawSubset = spikesToDraw;
end
hold(handle,'on');
plot(1:params.spikeLength, spikesToDrawSubset', 'color', spikeColor); % HM edit
vline(95,'r-');
ylabel(['n=' num2str(size(spikesToDraw,1))]);
title(['Cluster ' num2str(thiscluster)]);
axis([1,256,params.yAxisLim(1),params.yAxisLim(2)]);
% Make sure line for average waveform is in a different color
avColor='w';
plot(1:params.spikeLength, mean(spikesToDraw),avColor, 'linewidth', 2);
set(gca,'XTickLabel',{});
hold(handle,'off');








