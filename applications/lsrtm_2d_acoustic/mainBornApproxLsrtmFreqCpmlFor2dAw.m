% MAINBORNAPPROXLSRTMFREQCPMLFOR2DAW simulates the least-squares reverse
% time migration (LSRTM) with 2-d acoustic wave in frequency domain based
% on the CPML absorbing boundary condition, using Gauss-Newton method where
% the Hessian matrix is approximated by its diagonal terms based on the
% Born approximation
%
% The LSRTM in frequency domain is used to solve the following problem:
% Given a smooth but obscure velocity model and the received data on
% surface, the true but unknown velocity model is to be approximated by
% estimating the scatter field during iterations.
%
% System background
% ====================================================================================================
%
% m = m_0 + delta_m, delta_m is model perturbation
% PDE for true field u:         (m(x)(d^2/dt^2) - Laplacian)u(x, t; xs) = f(x, t; xs)
% PDE for incident field u_0:   (m_0(x)(d^2/dt^2) - Laplacian)u_0(x, t; xs) = f(x, t; xs)
% u = u_0 + u_sc, u_sc is scattered field
%
% Therefore, we have
% (m_0(x)(d^2/dt^2) - Laplacian)u_sc(y, t; xs) = - delta_m(x) * (d^2/dt^2)u(x, t; xs)
%
% In frequency domain
% (- m_0(x)w^2 - Laplacian)U_sc(y, jw; xs) = w^2 * delta_m(x) * U(x, jw; xs)
% whose solution is
% U_sc(y, jw; xs) = w^2 * \sum_x G_0(y, jw; x) * delta_m(x) * U(x, jw; xs)
% where G_0(y, jw; x) is the Green's function of m_0(x) from source x to
% receiver y
%
% U_0(y, jw; xs) = U(y, jw; xs) - U_sc(y, jw; xs)
%                = U(y, jw; xs) - w^2 * \sum_x G_0(y, jw; x) * delta_m(x) * U(x, jw; xs)
%                = (I + A)U(y, jw; xs)
% where operator (matrix) A is composed by (rows of) [- w^2 * G_0(y, jw; x) * delta_m(x)]
%
% Therefore, we have
% U = U_0 + U_sc = (I + A)^{-1} * U_0 ~= U_0 - A * U_0 = U_0 + U_1 by
% discarding quadratic and higher order approximation of the Taylor
% expansion and U_1 = - A * U_0 is the Born approximation of U_sc, i.e.,
% U_1(y, jw; xs) = w^2 * \sum_x G_0(y, jw; x) * delta_m(x) * U_0(x, jw; xs)
% which is the solution of
% (- m_0(x)w^2 - Laplacian)U_1(y, jw; xs) = w^2 * delta_m(x) * U_0(x, jw; xs)
%
% By expanding U_0(x, jw; xs) = G_0(x, jw; xs) * F(x, jw; xs) and the solution
% U_1 can be written in a linear form
% U_1(y, jw; xs) = w^2 * \sum_x F(x, jw; xs) * G_0(x, jw; xs) * G_0(y, jw; x) * delta_m(x), i.e., 
% U_1(y, jw; xs) = L * delta_m(x) where operator (matrix) L is composed of
% (rows of) [w^2 * F(x, jw; xs) * G_0(x, jw; xs) * G_0(y, jw; x)]
%
% The cost function is:
% J = 1/2 * \sum_w \sum_xs \sum_xr |U_1(xr, jw; xs) - U_sc(xr, jw; xs)|^2 + lambda * |delta_m(x)|^2
% where lambda * |delta_m(x)|^2 is for normalization
%
% ====================================================================================================
%
%
% Purpose
% ====================================================================================================
%
% To find an optimized delta_m(x) such that J is minimized and update the
% velocity model m
%
% ====================================================================================================
%
%
% Method
% ====================================================================================================
%
% J is minimized using Newton method in which the Hessian matrix is
% approximated by its diagonal elements (a.k.a. pseudo-Hessian)
%
% ====================================================================================================
%
%
% This matlab source file is free for use in academic research.
% All rights reserved.
%
% Written by Lingchen Zhu (zhulingchen@gmail.com)
% Center for Signal and Information Processing, Center for Energy & Geo Processing
% Georgia Institute of Technology

close all;
clear;
clc;


%% Full Wave Inversion Example
% in frequency domain

ALPHA = 0.75;
DELTA = 1e-4;
EPSILON = 1;
FREQTHRES = 2;
MAXITER = 20;


%% Set path
run([fileparts(pwd), '/setpath']);


%% Read in velocity model data
filenameVelocityModel = [model_data_path, '/velocityModel.mat'];
[pathVelocityModel, nameVelocityModel] = fileparts(filenameVelocityModel);
load(filenameVelocityModel); % velocityModel
[nz, nx] = size(velocityModel);

% smooth velocity model used average filter
filenameVelocityModelSmooth = [model_data_path, '/velocityModelSmooth.mat'];
load(filenameVelocityModelSmooth); % velocityModelSmooth

nBoundary = 20;
% % a more smooth velocity model for FWI
% VS = extBoundary(velocityModelSmooth, nBoundary, 2);
% VS = [repmat(VS(1, :), nBoundary, 1); VS];
% nAvgSize = [1, 1];
% hImageSmooth = fspecial('average', nAvgSize);
% VS = imfilter(VS, hImageSmooth);
% velocityModelSmooth = VS(nBoundary+1:end-nBoundary, nBoundary+1:end-nBoundary);

dx = 10;
dz = 10;
x = (1:nx) * dx;
z = (1:nz) * dz;

% grids and positions of shot array
shotArrType = 'uniform';
idxShotArrLeft = 1;
idxShotArrRight = nx;
nShots = nx;
if (strcmpi(shotArrType, 'uniform'))
    xShotGrid = (idxShotArrLeft:ceil((idxShotArrRight - idxShotArrLeft + 1)/nShots):idxShotArrRight);
elseif (strcmpi(shotArrType, 'random'))
    xShotGrid = (idxShotArrLeft:idxShotArrRight);
    xShotGrid = sort(xShotGrid(randperm(idxShotArrRight - idxShotArrLeft + 1, nShots)));
else
    error('Shot array deployment type error!');
end
zShotGrid = ones(1, nShots); % shots are on the surface
xShot = xShotGrid * dx;
zShot = zShotGrid * dz;

% grids and positions of receiver array (all on the surface)
recArrType = 'uniform';
idxRecArrLeft = 1;
idxRecArrRight = nx;
nRecs = nx;
if (strcmpi(recArrType, 'uniform'))
    xRecGrid = (idxRecArrLeft:ceil((idxRecArrRight - idxRecArrLeft + 1)/nRecs):idxRecArrRight);
elseif (strcmpi(recArrType, 'random'))
    xRecGrid = (idxRecArrLeft:idxRecArrRight);
    xRecGrid = sort(xRecGrid(randperm(idxRecArrRight - idxRecArrLeft + 1, nRecs)));
else
    error('Receiver array deployment type error!');
end
zRecGrid = ones(1, nRecs); % receivers are on the surface
xRec = xRecGrid * dx;
zRec = zRecGrid * dz;


%% Create shot gathers
% Use the velocity model to simulate a seismic survey.  The wave equations
% is solved using finite differences with a continuous source function
vmin = min(velocityModel(:));
vmax = max(velocityModel(:));

% calculate time step dt from stability crierion for finite difference
% solution of the wave equation.
dt = ALPHA * (dz/vmax/sqrt(2));

% determine time samples nt from wave travelime to depth and back to
% surface
nt = round(sqrt((dx*nx)^2 + (dz*nz)^2)*2/vmin/dt + 1);
t  = (0:nt-1).*dt;
nfft = 2^(nextpow2(nt));
dw = 2*pi/nfft;
w = (-pi:dw:pi-dw)/dt; % analog angular frequency \omega = [-pi, pi)/dt

% add region around model for applying absorbing boundary conditions
V = extBoundary(velocityModel, nBoundary, 2);
VS = extBoundary(velocityModelSmooth, nBoundary, 2);

% dimension of frequency-domain solution
nLength = nz * nx;
nLengthWithBoundary = (nz + nBoundary) * (nx + 2*nBoundary);

% number of approximation order for differentiator operator
nDiffOrder = 2;

% Define analog frequency parameter for ricker wavelet
f = 20;


%% Shot data recording at the surface
% generate shot signal
rw1dTime = zeros(1, nt);
for ifreq = 1:length(f)
    rw1dTime = rw1dTime + ricker(f(ifreq), nt, dt);
end
rw1dFreq = fftshift(fft(rw1dTime, nfft), 2);
% find active frequency set with FFT amplitude larger than the threshold
activeW = find(abs(rw1dFreq) > FREQTHRES);
activeW = activeW(activeW > nfft / 2 + 1); % choose f > 0Hz

dataTrueFreq = zeros(nRecs, nShots, length(activeW));
dataDeltaFreq = zeros(nRecs, nShots, length(activeW));

% shot positions on extended velocity model
xs = xShotGrid + nBoundary;
zs = zShotGrid;

% receiver positions on extended velocity model
xr = xRecGrid + nBoundary;
zr = zRecGrid;



%% Start a pool of Matlab workers
numCores = feature('numcores');
if isempty(gcp('nocreate')) % checking to see if my pool is already open
    myPool = parpool(numCores);
end


%% generate shot record and save them in frequency domain
parfor idx_w = 1:length(activeW)
    
    iw = activeW(idx_w);
    
    fprintf('Generate %d frequency responses at f(%d) = %fHz ... ', nShots, iw, w(iw)/(2*pi));
    tic;
    
    % received true data for all shots in frequency domain for current frequency
    sourceFreq = zeros(nLengthWithBoundary, nShots);
    sourceFreq((xs-1)*(nz+nBoundary)+zs, :) = rw1dFreq(iw) * eye(nShots, nShots);
    [~, snapshotTrueFreq] = freqCpmlFor2dAw(V, sourceFreq, w(iw), nDiffOrder, nBoundary, dz, dx);
    % get received data on the receivers
    dataTrueFreq(:, :, idx_w) = snapshotTrueFreq((xr-1)*(nz+nBoundary)+zr, :);
    
    % calculate smooth data for all shots in frequency domain for current frequency
    sourceFreq = zeros(nLengthWithBoundary, nShots);
    sourceFreq((xs-1)*(nz+nBoundary)+zs, :) = rw1dFreq(iw) * eye(nShots, nShots);
    [~, snapshotSmoothFreq] = freqCpmlFor2dAw(VS, sourceFreq, w(iw), nDiffOrder, nBoundary, dz, dx);
    % get calculated data on the receivers
    dataDeltaFreq(:, :, idx_w) = dataTrueFreq(:, :, idx_w) - snapshotSmoothFreq((xr-1)*(nz+nBoundary)+zr, :);
    
    timePerFreq = toc;
    fprintf('elapsed time = %fs\n', timePerFreq);
    
end

% save received surface data
filenameDataTrueFreq = [pathVelocityModel, '/dataTrueFreq.mat'];
save(filenameDataTrueFreq, 'dataTrueFreq', '-v7.3');

filenameDataDeltaFreq = [pathVelocityModel, '/dataDeltaFreq0.mat'];
save(filenameDataDeltaFreq, 'dataDeltaFreq', '-v7.3');

% clear variables and functions from memory
clear('dataTrueFreq');
clear('dataDeltaFreq');
clear('sourceTime');


%% Full wave inversion (FWI)
% (1/v^2)*(d^2)u(z, x, t)/dt^2  = (d^2)u(z, x, t)/dz^2 + (d^2)u(z, x, t)/dx^2 + s(z, x, t)
%                                           |
%                                   (Fourier transform), (d^n)f(t)/dt^n -> ((jw)^n)F(jw)
%                                           |
%                                           V
% (w^2)/(v^2)*U(z, x, jw) + (d^2)U(z, x, jw)/dz^2 + (d^2)U(z, x, jw)/dx^2 = -S(z, x, jw)
%
% Green's function is the impulse response of the wave equation.

% generate impulse shot signal

modelOld = zeros(nz + nBoundary, nx + 2*nBoundary);
modelNew = 1./(VS.^2);

hFigOld = figure(1);
hFigNew = figure(2);

%% LSRTM main iteration
iter = 1;
while(norm(modelNew - modelOld, 'fro') / norm(modelOld, 'fro') > DELTA && iter <= MAXITER)
    
    modelOld = modelNew;
    vmOld = 1./sqrt(modelOld);
    load(filenameDataDeltaFreq);
    
    % an approximated diagonal Hessian matrix
    hessianDiag = zeros(nLengthWithBoundary, 1);
    % hessianMat = zeros(nLength, nLength);
    % migrated image
    mig = zeros(nLengthWithBoundary, 1);
    
    figure(hFigOld);
    imagesc(x, z, vmOld(1:end-nBoundary, nBoundary+1:end-nBoundary));
    xlabel('Distance (m)'); ylabel('Depth (m)');
    title('Previous Velocity Model');
    colormap(seismic); colorbar; caxis manual; caxis([vmin, vmax]);
    
    % update the velocity model with least-squares
    parfor idx_w = 1:length(activeW)
        
        iw = activeW(idx_w);
        
        fprintf('Generate %d Green''s functions at f(%d) = %fHz ... ', nShots, iw, w(iw)/(2*pi));
        tic;
        
        % Green's function for every shot
        sourceFreq = zeros(nLengthWithBoundary, nShots);
        sourceFreq((xs-1)*(nz+nBoundary)+zs, :) = eye(nShots, nShots);
        [~, greenFreqForShot] = freqCpmlFor2dAw(vmOld, sourceFreq, w(iw), nDiffOrder, nBoundary, dz, dx);
        
        % Green's function for every receiver
        sourceFreq = zeros(nLengthWithBoundary, nRecs);
        sourceFreq((xr-1)*(nz+nBoundary)+zr, :) = eye(nRecs, nRecs);
        [~, greenFreqForRec] = freqCpmlFor2dAw(vmOld, sourceFreq, w(iw), nDiffOrder, nBoundary, dz, dx);
        
        % calculate the pseudo-Hessian matrix, which is the diagonal elements of Hessian matrix
        hessianDiag = hessianDiag + w(iw)^4 * abs(rw1dFreq(iw))^2 ...
            * sum(abs(greenFreqForShot).^2 .* (abs(greenFreqForRec).^2 * ones(nRecs, nShots)), 2);
        
        % % the true Hessian matrix
        % hessianMat = hessianMat + w(iw)^4 * abs(rw1dFreq(iw))^2 ...
        %     * (greenFreqForShot * greenFreqForShot') .* (greenFreqForRec * greenFreqForRec');
        
        % for ixs = 1:nShots
        %     for ixr = 1:nRecs
        %         hessianDiag2 = hessianDiag2 + real(w(iw)^4 * abs(rw1dFreq(iw))^2 ...
        %             * abs(greenFreqForShot(:, ixs)).^2 .* abs(greenFreqForRec(:, ixr)).^2);
        %     end
        % end
        
        % calculate the migrated image using dataDeltaFreq
        mig = mig + w(iw)^2 * rw1dFreq(iw) * sum(greenFreqForShot .* (greenFreqForRec * conj(dataDeltaFreq(:, :, idx_w))), 2);
        
        % for ixs = 1:nShots
        %     for ixr = 1:nRecs
        %         grad2 = grad2 + real(w(iw)^2 * rw1dFreq(iw) * conj(dataDeltaFreq(ixr, ixs, iw)) ...
        %             * greenFreqForShot(:, ixs) .* greenFreqForRec(:, ixr));
        %     end
        % end
        
        timePerFreq = toc;
        fprintf('elapsed time = %fs\n', timePerFreq);
        
    end
    
    % save the pseudo-Hessian matrix
    filenameHessianDiag = [pathVelocityModel, sprintf('/hessianDiag%d.mat', iter)];
    save(filenameHessianDiag, 'hessianDiag', '-v7.3');
    
    % save the migrated image
    filenameMig = [pathVelocityModel, sprintf('/mig%d.mat', iter)];
    save(filenameMig, 'mig', '-v7.3');
    
    lambda = 5 * max(hessianDiag);
    dm = EPSILON * (real(mig) ./ real(hessianDiag + lambda * ones(nLengthWithBoundary, 1)));
    
    % updated model
    modelOld = reshape(modelOld, nLengthWithBoundary, 1);
    modelNew = modelOld + dm;
    modelOld = reshape(modelOld, nz + nBoundary, nx + 2*nBoundary);
    modelNew = reshape(modelNew, nz + nBoundary, nx + 2*nBoundary);
    % modelNew(modelNew < 1/vmax^2) = 1/vmax^2;
    % modelNew(modelNew > 1/vmin^2) = 1/vmin^2;
    vmNew = 1./sqrt(modelNew);
    
    figure(hFigNew);
    imagesc(x, z, vmNew(1:end-nBoundary, nBoundary+1:end-nBoundary));
    xlabel('Distance (m)'); ylabel('Depth (m)');
    title('Updated Velocity Model');
    colormap(seismic); colorbar; caxis manual; caxis([vmin, vmax]);
    % save current updated velocity model
    filenameVmNew = [pathVelocityModel, sprintf('/vmNew%d.mat', iter)];
    save(filenameVmNew, 'vmNew', 'modelNew', 'dm', '-v7.3');
    
    
    %% debug begin
    %     % this code fragment implemented the original matrix L and bigL, which
    %     % is the stack of L's with respect to all xr and xs's. The code and its
    %     % results are proved to be the same with the above code but runs much
    %     % slower than that due to lots of large matrix multiplications. You can
    %     % regard this code fragment as the direct implementation of the
    %     % gradient and Hessian matrix of the cost function. We leave them here
    %     % for reference.
    %
    %     load(filenameDataDeltaFreq);
    %     L = zeros(1, nLength);
    %     bigL = zeros(nShots * nRecs, nLength);
    %     hessianTrue = zeros(nLength, nLength);
    %     hessianTrue2 = zeros(nLength, nLength);
    %     mig = zeros(nLength, 1);
    %     mig2 = zeros(nLength, 1);
    %     u1 = zeros(nShots, nRecs);
    %     u1_bak = zeros(nShots, nRecs);
    %     gradVerify = zeros(nLength, 1);
    %     gradVerify_bak = zeros(nLength, 1);
    %     for iw = activeW
    %
    %         if (iw == nfft / 2 + 1)
    %             % skip f = 0Hz
    %             continue;
    %         end
    %
    %         fprintf('Generate %d Green''s functions at f(%d) = %fHz ... ', nShots, iw, w(iw)/(2*pi));
    %         tic;
    %         
    %         % Green's function for every shot
    %         sourceFreq = zeros(nLengthWithBoundary, nShots);
    %         sourceFreq((xs-1)*(nz+nBoundary)+zs, :) = eye(nShots, nShots);
    %         [~, greenFreqForShot] = freqCpmlFor2dAw(vmOld, sourceFreq, w(iw), nDiffOrder, nBoundary, dz, dx);
    %         
    %         % Green's function for every receiver
    %         sourceFreq = zeros(nLengthWithBoundary, nRecs);
    %         sourceFreq((xr-1)*(nz+nBoundary)+zr, :) = eye(nRecs, nRecs);
    %         [~, greenFreqForRec] = freqCpmlFor2dAw(vmOld, sourceFreq, w(iw), nDiffOrder, nBoundary, dz, dx);
    %
    %         % calculate bigL matrix
    %         [meshXRec, meshXShot] = meshgrid(xRecGrid, xShotGrid);
    %         bigL = w(iw)^2 * rw1dFreq(iw) * (greenFreqForShot(:, meshXShot(:)).' .* greenFreqForRec(:, meshXRec(:)).');
    %         % the true Hessian matrix 1
    %         hessianTrue = hessianTrue + bigL' * bigL;
    %         % the true Hessian matrix 2
    %         hessianTrue2 = hessianTrue2 + w(iw)^4 * abs(rw1dFreq(iw))^2 ...
    %             * ((conj(greenFreqForShot) * greenFreqForShot.') .* (conj(greenFreqForRec) * greenFreqForRec.'));
    %         mig = mig + bigL' * reshape(dataDeltaFreq(:, :, iw).', nShots * nRecs, 1);
    %         mig2 = mig2 + w(iw)^2 * (-conj(rw1dFreq(iw))) * sum(conj(greenFreqForShot) .* (conj(greenFreqForRec) * dataDeltaFreq(:, :, iw)), 2);
    %         % dm = (real(hessianTrue) \ real(rtm));
    %
    %         % u1 = w(iw)^2 * rw1dFreq(iw) * (repmat(dm, 1, nShots) .* greenFreqForShot).' * greenFreqForRec;
    %         % u1 = bigL * dm;
    %         % u1 = reshape(u1, nShots, nRecs);
    %
    %         % for ixs = 1:nShots
    %         %     for ixr = 1:nRecs
    %         %         L = w(iw)^2 * rw1dFreq(iw) * (greenFreqForShot(:, ixs).' .* greenFreqForRec(:, ixr).');
    %         %         u1_bak(ixs, ixr) = L * dm;
    %         %     end
    %         % end
    %
    %         % bias = u1 - dataDeltaFreq(:, :, iw).';
    %         % bias = reshape(bias, nShots * nRecs, 1);
    %         % gradVerify = gradVerify + real(bigL' * bias);
    %         % bias = reshape(bias, nShots, nRecs);
    %
    %         % for ixs = 1:nShots
    %         %     for ixr = 1:nRecs
    %         %         L = w(iw)^2 * rw1dFreq(iw) * (greenFreqForShot(:, ixs).' .* greenFreqForRec(:, ixr).');
    %         %         gradVerify_bak = gradVerify_bak + ...
    %         %             real(L' * bias(ixs, ixr));
    %         %     end
    %         % end
    %
    %         timePerFreq = toc;
    %         fprintf('elapsed time = %fs\n', timePerFreq);
    %     end
    %
    %     lambda = max(diag(hessianTrue));
    %     hessianTrue = hessianTrue + lambda * eye(nLength, nLength);
    %
    %     % updated model
    %     modelOld = reshape(modelOld, nLength, 1);
    %     modelNew = modelOld + EPSILON * (real(hessianTrue) \ real(mig));
    %     modelOld = reshape(modelOld, nz, nx);
    %     modelNew = reshape(modelNew, nz, nx);
    %     modelNew(modelNew < 1/vmax^2) = 1/vmax^2;
    %     modelNew(modelNew > 1/vmin^2) = 1/vmin^2;
    %     vmNew = 1./sqrt(modelNew);
    %     vmNew = extBoundary(vmNew, nBoundary, 2);
    %
    %     figure(hFigNew);
    %     imagesc(x, z, vmNew(1:end-nBoundary, nBoundary+1:end-nBoundary));
    %     xlabel('Distance (m)'); ylabel('Depth (m)');
    %     title('Updated Velocity Model');
    %     colormap(seismic); colorbar; caxis manual; caxis([vmin, vmax]);
    %     % save current updated velocity model
    %     % filenameVmNew = [pathVelocityModel, sprintf('/vmNew%d.mat', iter)];
    %     % save(filenameVmNew, 'vmNew', 'modelNew', 'dm', '-v7.3');
    %
    %     dataDeltaFreq = zeros(nRecs, nShots, nfft);
    %% debug end
    
    clear('dataDeltaFreq');
    % load received surface data
    load(filenameDataTrueFreq);
    
    % update dataDeltaFreq
    dataDeltaFreq = zeros(nRecs, nShots, nfft);
    parfor idx_w = 1:length(activeW)
        
        iw = activeW(idx_w);
        
        fprintf('Generate %d frequency responses at f(%d) = %fHz ... ', nShots, iw, w(iw)/(2*pi));
        tic;
        
        % calculate smooth data for all shots in frequency domain for current frequency
        sourceFreq = zeros(nLengthWithBoundary, nShots);
        sourceFreq((xs-1)*(nz+nBoundary)+zs, :) = rw1dFreq(iw) * eye(nShots, nShots);
        [ASmooth, snapshotSmoothFreq] = freqCpmlFor2dAw(vmNew, sourceFreq, w(iw), nDiffOrder, nBoundary, dz, dx);
        % get calculated data on the receivers
        dataDeltaFreq(:, :, idx_w) = dataTrueFreq(:, :, idx_w) - snapshotSmoothFreq((xr-1)*(nz+nBoundary)+zr, :);
        
        timePerFreq = toc;
        fprintf('elapsed time = %fs\n', timePerFreq);
        
    end
    
    filenameDataDeltaFreq = [pathVelocityModel, sprintf('/dataDeltaFreq%d.mat', iter)];
    save(filenameDataDeltaFreq, 'dataDeltaFreq', '-v7.3');
    
    % clear variables and functions from memory
    clear('dataTrueFreq');
    clear('dataDeltaFreq');
    clear('sourceTime');
    
    fprintf('Full-wave inversion iteration no. %d, model norm difference = %.6f\n', ...
        iter, norm(modelNew - modelOld, 'fro') / norm(modelOld, 'fro'));
    
    iter = iter + 1;
    
end

%% Terminate the pool of Matlab workers
delete(gcp('nocreate'));
