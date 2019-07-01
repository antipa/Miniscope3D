% Read in PSF
% This is designed to work with measurements in a folder, then in a
% parallel folder, save the recons (i.e. measurements../recons/)
data_path = 'D:\Kyrollos\RandoscopeNanoscribe\measurements';   %<--folder where the measurements are

meas_name = 'res_target_1_MMStack_Pos0.ome.tif';    %<--- name of measurement
bg_name = 'bck_res_target_1_MMStack_Pos0.ome.tif';

meas_path = [data_path,'/',meas_name];
bg_path = [data_path,'/',bg_name];

psf_path = 'D:\Kyrollos\RandoscopeNanoscribe\RandoscopeNanoscribe\Miniscope3D\psf_svd_12comps_23z_240xy_20190619';
comps_path = [psf_path,'/comps.mat'];
weights_path = [psf_path,'/weights.mat'];

h_in = load(comps_path);
weights_in = load(weights_path);

%%

params.meas_depth = 41;    %If using 3D tiff, which slice was processed?
params.ds_z = 1;   %z downsampling ratio
params.meas_bias = 0;
init_style = 'zeros';   %Use 'loaded' to load initialization, 'zeros' to start from scratch. Admm will run 2D deconv, then replicate result to all time points
params.ds = 4;  % Global downsampling ratio (i.e.final image-to-sensor ratio)
params.ds_psf = 1;   %PSf downsample ratio (how much to further downsample -- if preprocessing included downsampling, use 1) 
params.ds_meas = 4;   % How much to further downsample measurement?
params.z_range = 10;  %Range of z slices to be solved for. If this is a scalar, 2D
params.rank = 12;
useGpu = 1;
params.psf_norm = 'fro';   %Use max, slice, fro, or none




h = squeeze(h_in.stack_comps(:,:,params.z_range,1:params.rank));
weights = squeeze(weights_in.stack_weights_interp(:,:,params.z_range,1:params.rank));


switch lower(params.psf_norm)
    case('max')
        h = h/max(h(:));
    case('none')
    case('fro')
        h = h/norm(vec(h));
end




% Read in data

data_raw = double(read_tiff_stack(meas_path,params.ds_meas,params.meas_depth));
bg_in =  double(read_tiff_stack(bg_path,params.ds_meas,params.meas_depth));
data_in = data_raw - bg_in;
b = data_in/max(data_in(:));

%%
% data_r = data_in(:,:,1);
% data_g = data_in(:,:,2);
% data_b = data_in(:,:,3);


%Nx = size(h,2);
%Ny = size(h,1);
if numel(size(h)) == 3
    [Ny, Nx, Nr] = size(h);
    Nz = 1;
else
    [Ny, Nx, Nz, Nr] = size(h);
end

%define crop and pad operators to handle 2D fft convolution
pad2d = @(x)padarray(x,[size(h,1)/2,size(h,2)/2],0,'both');
cc = gpuArray(size(h,2)/2+1):(3*size(h,2)/2);
rc = gpuArray(size(h,1)/2+1):(3*size(h,1)/2);
crop2d = @(x)x(rc,cc);







if strcmpi(init_style, 'zeros')
    xinit = zeros(Ny, Nx, Nz);
elseif strcmpi(init_style,'loaded')
    xinit = imnormalized(:,:,:);
elseif strcmpi(init_style,'admm')
    xinit_2d = gpuArray(single(zeros(Ny, Nx, 3))); 

    for n = 1:3
        xinit_2d(:,:,n) = admm2d_solver(gpuArray(single(b(:,:,n))), gpuArray(single(h(:,:,n))),[],.001); 
       
        imagesc(2*xinit_2d/max(xinit_2d(:)))
    end
end





%%

options.color_map = 'parula';

    

options.convTol = 15e-12;

%options.xsize = [256,256];
options.maxIter = 2000;
options.residTol = 5e-5;
options.momentum = 'nesterov';
options.disp_figs = 1;
options.disp_fig_interval = 20;   %display image this often
if Nz == 1
    options.xsize = [Ny, Nx];
else
    options.xsize=[Ny, Nx, Nz];
end
options.print_interval = 5;



h1 = figure(1);
clf
options.fighandle = h1;
nocrop = @(x)x;
options.known_input = 0;




H = fft2(ifftshift(ifftshift(h,1),2));
Hconj = conj(H);
if useGpu
    H = gpuArray(H);
    Hconj = gpuArray(Hconj);
    weights = gpuArray(weights);
end

if Nz > 1
    A = @(x)A_svd_3d(x, weights,H);

    Aadj = @(y)A_adj_svd_3d(y, weights, Hconj);
elseif Nz == 1
    A = @(x)A_svd(H, weights, x, nocrop);
    Aadj = @(y)A_adj_svd(Hconj,weights,y,nocrop);
end

if useGpu
    grad_handle = @(x)linear_gradient_b(x, A, Aadj, gpuArray(single(b)));
else
    grad_handle = @(x)linear_gradient_b(x, A, Aadj, b(:,:,cindex));
end
%%
%Prox
%prox_handle = @(x)deal(x.*(x>=0), abs(sum(sum(sum(x(x<0))))));
tau1 = gpuArray(1e-7);   %.000005 works pretty well for v1 camera, .0002 for v2
tau_iso = gpuArray(.25e-4);
pars.z_tv_weight = 3;    %z weighting in anisotropic TV
tau2 = .1;
TVnorm3d = @(x)sum(sum(sum(abs(x))));
%prox_handle = @(x)deal(1/3*(x.*(x>=0) + soft(x, tau2) + tv3dApproxHaar(x, tau1)), TVnorm3d(x));

if params.ds == 4
    options.stepsize = .1e-3;
    
end

if Nz>1
    prox_handle = @(x)deal(1/2*(max(x,0) + tv3d_iso_Haar(x, tau1, pars.z_tv_weight)), tau1*TVnorm3d(x));
elseif Nz == 1
    prox_handle = @(x)deal(.5*tv2d_aniso_haar(x,tau1*options.stepsize) + ...
        .5*max(x,0), tau1*options.stepsize*TVnorm(x));
end
TVpars.epsilon = 1e-7;
TVpars.MAXITER = 100;
TVpars.alpha = .3;
%prox_handle = @(x)deal(hsvid_TV3DFista(x, tau_iso, 0, 10, TVpars) , hsvid_TVnorm3d(x));

if strcmpi(init_style, 'zeros')
    xinit = zeros(Ny, Nx, Nz);
    
end

if useGpu

    TVpars.epsilon = gpuArray(TVpars.epsilon);
    TVpars.MAXITER = gpuArray(TVpars.MAXITER);
    TVpars.alpha = gpuArray(TVpars.alpha);
    xinit = gpuArray(single(xinit));
    [xhat, f2] = proxMin(grad_handle,prox_handle,xinit,gpuArray(single(b)),options);
else 
    [xhat, f2] = proxMin(grad_handle,prox_handle,xinit,b,options);
end




%%


datestamp = datetime;
date_string = datestr(datestamp,'yyyy-mmm-dd_HHMMSS');
save_str = ['../recons/',date_string,'_',meas_name(1:end-4)];
full_path = fullfile(data_path,save_str);
mkdir(full_path);


%%
imout = gather(xhat/prctile(xhat(:),99.99));
imbase = meas_name(1:end-4);
mkdir([full_path, '/png/']);
filebase = [full_path, '/png/', imbase];
out_names = {};
for n= 1:size(imout,3)
    out_names{n} = [filebase,'_',sprintf('%.3i',n),'.png'];
    imwrite(imout(:,:,n),out_names{n});
    fprintf('writing image %i of %i\n',n,size(xhat,3))
end

fprintf('zipping...\n')
zip([full_path, '/png/', imbase],out_names)
fprintf('done zipping\n')
%%
fprintf('writing .mat\n')
save([full_path,'/',meas_name(1:end-4),'_',date_string,'.mat'], 'tau_iso','TVpars','xhat', 'options', 'h', 'b','params','options','-v7.3')
fprintf('done writing .mat\n')
