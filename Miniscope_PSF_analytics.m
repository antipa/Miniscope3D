%%
pth = 'D:\Randoscope\dataforrebuttal\PSFs';
in = load([pth,'\psf_uni_middle.mat']);
psf_stack_uni = permute(flipud(in.psf_noaber_uni_mid_ds), [2 3 1]);


in = load([pth,'\psf_multi_middle.mat']);
%psf_stack_rando = permute(in.psf_montebest_ds, [2 3 1]);
psf_stack_rando = permute(flipud(in.psf_noaber_multi_mid_ds), [2 3 1]);


in = load([pth,'\psf_regular_middle.mat']);
psf_stack = permute(flipud(in.psf_noaber_reg_mid_ds), [2 3 1]);
h6 = figure(6),clf
h1 = figure(1),clf
h5 = figure(5),clf
Ascore_reg = []
Ascore_rand = []
Ascore_uni = []
ripple_reg = []
ripple_rando = []
ripple_uni = []

[X,Y] = meshgrid(-255.5:1:255.5,-255.5:1:255.5);
c = sqrt(X.^2+Y.^2)<=100;
fftcorr = @(x,y)gather(real(ifft2(fft2(ifftshift(x)).*conj(fft2(y)))));
c2 = sqrt(X.^2+Y.^2)<=70;
c2 = fftcorr(c2,c2);

c2 = gpuArray(single(c2/max(max(c2))));
C2 = ifft2(c2);
ripple_err = @(x,c)gather(norm(x - c/max(c(:))*max(x(:)),'fro'));
Nz =72;
Astar = @(x)c.*(1./(abs(x)+.00001));

for zplane = 1:Nz
    %zplane = 24
    
    psf_uni=psf_stack_uni(:,:,zplane);%6use 20 and 60
    psf_uni = psf_uni/sum(sum(psf_uni));
    
    psf_rando=psf_stack_rando(:,:,zplane);% use 20 and 60, end-5 for noise sims
    psf_rando = psf_rando/sum(sum(psf_rando));
    
    regoffset = 0;
    psf_regular = psf_stack(:,:,zplane+regoffset);  %use 72 and 32
    psf_regular = psf_regular/sum(sum(psf_regular));
    
    set(0,'CurrentFigure',h1)
    clf
    subplot(1,3,1)
    imagesc(psf_regular)
    axis image
    caxis([0 .002]);
    title('reg')
    
    subplot(1,3,2)
    imagesc(psf_uni)
    axis image
    caxis([0 .002]);
    title('uni')
    
    subplot(1,3,3)
    imagesc(psf_rando)
    axis image
    caxis([0 .002]);
    title('rando')
    
    pad2d = @(x)padarray(x,[size(x,1)/2,size(x,2)/2],'both');
    
    crop2d = @(x)x(size(x,1)/4+1:3*size(x,1)/4, size(x,2)/4+1:3*size(x,2)/4);
    
    %
    % psfacorr = crop2d(xcorr2(psf_regular,psf_regular));
    % psfacorr_rando = crop2d(xcorr2(psf_rando,psf_rando));
    % psfacorr_uni = crop2d(xcorr2(psf_uni,psf_uni));
    
    psfspect = gather(fftshift(abs(fft2(psf_regular)).^2));
    psfspect_rando = gather(fftshift(abs(fft2(psf_rando)).^2));
    psfspect_uni = gather(fftshift(abs(fft2(psf_uni)).^2));
    
    ripple_rando(zplane) = ripple_err(psf_rando,c2);
    ripple_reg(zplane) = ripple_err(psf_regular,c2);
    ripple_uni(zplane) = ripple_err(psf_uni,c2);
    
    nbins = 200;
    [psavg, avgbins] = radialavg(abs(psfspect),nbins);
    [psavg_rando, avgbins] = radialavg(abs(psfspect_rando),nbins);
    [psavg_uni,avgbins] = radialavg(abs(psfspect_uni),nbins);
    set(0,'CurrentFigure',h5);
    clf
    plot(avgbins,psavg)
    hold on
    plot(avgbins,psavg_rando)
    plot(avgbins,psavg_uni)
    legend('reg','designed','uni')
    axis([0 .5 0 .1])
    hold off
    
    
    
    
    
    Astar_reg_im =Astar(psfspect);
    Astar_rand_im = Astar(psfspect_rando);
    Astar_uni_im = Astar(psfspect_uni);
    Ascore_reg(zplane) = sum(sum(Astar_reg_im));
    Ascore_rand(zplane) = sum(sum(Astar_rand_im));
    Ascore_uni(zplane) = sum(sum(Astar_uni_im));
    [Astar_reg, avgbins] = radialavg(Astar_reg_im,nbins);
    [Astar_rand, avgbins] = radialavg(Astar_rand_im,nbins);
    [Astar_uni, ~] = radialavg(Astar_uni_im, nbins);
    acorr_reg = real(ifft2(ifftshift(psfspect)));
    acorr_uni = real(ifft2(ifftshift(psfspect_uni)));
    acorr_rand = real(ifft2(ifftshift(psfspect_rando)));
    if zplane == 1
        Astar_reg_mat = Astar_reg;
        Astar_uni_mat = Astar_uni;
        Astar_rand_mat = Astar_rand;
        acorrslice_reg = acorr_reg(1,:);
        acorrslice_uni = acorr_uni(1,:);
        acorrslice_rand = acorr_rand(1,:);
    else
    
        Astar_reg_mat = cat(1,Astar_reg_mat,Astar_reg);
        Astar_uni_mat = cat(1,Astar_uni_mat,Astar_uni);
        Astar_rand_mat = cat(1,Astar_rand_mat,Astar_rand);
        acorrslice_reg = cat(1,acorrslice_reg,acorr_reg(1,:));
        acorrslice_uni = cat(1,acorrslice_uni,acorr_uni(1,:));
        acorrslice_rand = cat(1,acorrslice_rand,acorr_rand(1,:));
        
    end
    
    set(0,'CurrentFigure',h6)
    semilogy(avgbins,Astar_reg)
    hold on
    semilogy(avgbins,Astar_rand)
    semilogy(avgbins,Astar_uni)
    legend(sprintf('reg %.2g',Ascore_reg(zplane)),...
        sprintf('opt %.2g',Ascore_rand(zplane)),...
        sprintf('uni %.2g',Ascore_uni(zplane)))
    hold off
    drawnow
end
%%
px = 4;  %Pixel size in microns/pixel in sensor space
Mag = 5.2;   %Magnification
px_obj = px/Mag;
zvec = (1:72) * 5;
sm = 1;
filt_kern = 1/sm*ones(1,sm);
Ascore_reg_sm = filter(filt_kern,1,medfilt1(Ascore_reg,1));
Ascore_uni_sm = filter(filt_kern,1,medfilt1(Ascore_uni,1));
Ascore_rand_sm = filter(filt_kern,1,medfilt1(Ascore_rand,1));
figure(7),clf

semilogy(zvec,Ascore_reg_sm)
hold on
semilogy(zvec,Ascore_uni_sm)
semilogy(zvec,Ascore_rand_sm)
legend('Regular','uni','design')
title('sum(1/|MTF|')
xlabel('depth \mu m')
xlim([0 360])
ylabel('sum(1/|MTF|)')
hold off

figure(8),clf

plot(ripple_reg)
hold on
plot(ripple_uni)
plot(ripple_rando)

legend('Regular','uni','design')
title('frequency space error')
hold off
mxc = 14;
sc = 1;
prep_acorr = @(x)imresize(x(:,1:mxc)./max(x,[],2),sc,'bicubic')

figure(9)
clf

subplot(1,3,1)
imagesc(prep_acorr(acorrslice_reg))
ylabel('depth')
axis image
title('reg')
subplot(1,3,2)
imagesc(prep_acorr(acorrslice_uni))
ylabel('depth')
axis image
title('uni')

subplot(1,3,3)
imagesc(prep_acorr(acorrslice_rand))
ylabel('depth')
axis image
title('designed')

colormap jet

temp = prep_acorr(acorrslice_reg);
 
yplot = ((1:size(temp,2))-1)/size(temp,2)*px_obj*mxc*2  %The *2 is to make it FWHM
xplot = ((1:size(temp,1))-1)*72*5/size(temp,1);
[Xplt,Yplt] = meshgrid(xplot,yplot);
fwhm_contour = @(x,pct)contour(Xplt,Yplt,rot90(x,-1),[pct pct])
figure(10)
clf
fwhm_contour((prep_acorr(acorrslice_reg)),0.5);
hold on
fwhm_contour((prep_acorr(acorrslice_uni)),0.5);
fwhm_contour((prep_acorr(acorrslice_rand)),0.5);

title('FWHM vs z')

% This stuff does it by counting pixels:
% acnorm_reg = prep_acorr(acorrslice_reg);
% acnorm_uni = prep_acorr(acorrslice_uni);
% acnorm_rand = prep_acorr(acorrslice_rand);
% make_fwhm = @(x,pct)sum(x>=pct,2);




% 
% fwhm_uni =make_fwhm(acnorm_uni,0.5)/sc/px_obj;
% fwhm_reg = make_fwhm(acnorm_rand,0.5)/sc/px_obj;
% plot(xplot,flipud(fwhm_uni))
% plot(xplot,flipud(fwhm_reg))
legend('Regular','unifocal','designed')
hold off 

%%

%% Make axial correlation plots for resolution analysis

Nz = size(psf_stack_uni,3);
axmat_uni = zeros(Nz,Nz);
axmat_regular = zeros(Nz,Nz);
axmat_rando = zeros(Nz,Nz);
corrmat_uni = zeros(Nz,Nz);
corrmat_regular =  zeros(Nz,Nz);
corrmat_rando = zeros(Nz,Nz);
%%
dot_prod = @(x,n,m)gather(sum(sum(x(:,:,n).*x(:,:,m))));
max_corr = @(x,n,m)max(max(fftcorr(x(:,:,n),x(:,:,m))));
figure(9),clf
for nn = 1:Nz
    for mm = nn:Nz
        axmat_uni(nn,mm) = dot_prod(psf_stack_uni,nn,mm);
        axmat_regular(nn,mm) = dot_prod(psf_stack,nn,mm);
        axmat_rando(nn,mm) = dot_prod(psf_stack_rando,nn,mm);
        corrmat_uni(nn,mm) = max_corr(psf_stack_uni,nn,mm);
        corrmat_regular(nn,mm) = max_corr(psf_stack,nn,mm);
        corrmat_rando(nn,mm) = max_corr(psf_stack_rando,nn,mm);
    end
    subplot(2,3,1)
    imagesc(axmat_uni)
    axis image
    
    title('uni')
    
    subplot(2,3,2)
    imagesc(axmat_regular)
    axis image
    
    title('regular')
    
    subplot(2,3,3)
    imagesc(axmat_rando)
    axis image
    
    title('rando')
    
    subplot(2,3,4)
    imagesc(corrmat_uni)
    axis image
    
    title('uni maxcorr')
    
    subplot(2,3,5)
    imagesc(corrmat_regular)
    axis image
    
    title('regular maxcorr')
    
    subplot(2,3,6)
    imagesc(corrmat_rando)
    axis image
    
    title('rando maxcorr')
    drawnow
    
end