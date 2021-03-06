function mvpaRunSearchlightRegressionWithinSubjects(nameIdx,dim,feature,label,nFold,dirHdr,dirSave,strSave)
% nameIdx: neighbor name (searchlight sphere file)
% feature: predictor matrix, X = [nSubjxcasePerSubject,nVoxel]
% label: response vector, Y = [nSubjxcasePerSubject,1]
% nFold: number of folds
% dirHdr: where header file is saved
% dirSave: directory for the output file (accuracy map)
% strSave: string attached to the output file name (cv"strSave".img)

% get GM indices
disp(['Neighbor name: ' nameIdx])
disp(['Save directory: ' dirSave])
fidIdx = fopen(nameIdx, 'r'); 
len = fread(fidIdx, 1, 'int32');
idxGM = fread(fidIdx, len, 'int32');

% spotlight search
count = 0;
accuracy = zeros(1, dim(1)* dim(2)* dim(3));
mse = zeros(1, dim(1)* dim(2)* dim(3));
labelTraining = repmat(label,nFold-1,1); % labels for training data points
labelTest = label; % labels for test data points
casePerRun = size(feature,1)/nFold;
while true
    [len, c] = fread(fidIdx, 1, 'int32');
    if c < 1
        break;
    end
    count = count + 1;
 
    % read in neighbor data
    centerId = fread(fidIdx, 1, 'int32');
    idx1 = fread(fidIdx, len, 'int32');        
    
    % read in feature
    F = feature(:, idx1);
    idx0 = find(sum(abs(F)) > 0); % eliminate all 0 vectors in T map
    if length(idx0) ~= length(idx1) 
        F = F(:, idx0);
    end
    
    % run searchlight
    if ~isempty(F) 
        zr = []; lossMSE = []; cfail = 0;
        
        % divide features into training & test data set
        for i = 1 : nFold
            training = []; test = [];
            for j = 1 : nFold
                x = F(j*casePerRun-casePerRun+1:j*casePerRun,:);
                if i == j % assign test data(subject)
                    test = x;
                else
                    training = [training; x];
                end
            end
            
            SVMModel = fitrsvm(training,labelTraining,'KernelFunction','linear','BoxConstraint',1); %'IterationLimit',1e8
            if SVMModel.ConvergenceInfo.Converged == 0 % check convergence
                cfail = cfail + 1;
            else % include the prediction results only when convergence is reached
                SVMPredict = predict(SVMModel,test); % model prediction
                r = corr(SVMPredict,labelTest); % correlation coefficient between model prediction & real label
                zr = [zr; 0.5*log((1+r)/(1-r))]; % Fisher's Z-transformed correlation coefficient
                                
                lossMSE = [lossMSE; loss(SVMModel,test,labelTest)]; % estimate mean squared error            
            end            
        end
        
        if ~isempty(nanmean(zr)) 
            accuracy(idxGM(centerId)) = nanmean(zr); % mean prediction accuracy
            mse(idxGM(centerId)) = nanmean(lossMSE); % mean MSE
        end
        
        if cfail > 0
            disp(['SVM model did not converge: voxel count = ' num2str(count) ', number of convergence failure = ' num2str(cfail)]);
        end
    end
    
    if mod(count, 500) == 1
        disp(sprintf('%d voxels searched, max accuracy %f', count, max(accuracy)));
    end
end
fclose(fidIdx);

% generate prediction accuracy map   
saveNameAccuracy = fullfile(dirSave, sprintf('cv%s.img', strSave));
fid = fopen(saveNameAccuracy, 'w');
fwrite(fid, accuracy, 'float32');                                                     
fclose(fid);
system(['copy ' dirHdr ' ' saveNameAccuracy(1:end - 4) '.hdr']); % copy header file         

% generate MSE map
saveNameMSE = fullfile(dirSave, sprintf('mse%s.img', strSave));
fid = fopen(saveNameMSE, 'w');
fwrite(fid, mse, 'float32');                                                     
fclose(fid);
system(['copy ' dirHdr ' ' saveNameMSE(1:end - 4) '.hdr']); % copy header file         


