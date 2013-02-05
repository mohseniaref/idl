
@resolve_nstatic_wind

;\\ Grab the latest allsky camera image
pro sdi_monitor_grab_allsky, maxElevation, error=error

	common sdi_monitor_common, global, persistent

	error = 0
	time = bin_date(systime(/ut))
	jd = js2jd(dt_tm_tojs(systime()))
	ut_fraction = (time(3)*3600. + time(4)*60. + time(5)) / 86400.
	sidereal_time = lmst(jd, ut_fraction, 0) * 24.
	sunpos, jd, RA, Dec
	sun_lat = Dec
	sun_lon = RA - (15. * sidereal_time)
	ll2rb, (station_info('pkr')).glon, (station_info('pkr')).glat, sun_lon, sun_lat, range, azimuth
	sun_elevation = refract(90 - (range * !radeg))
	if sun_elevation lt maxElevation then begin

		catch, error_status

	   ;\\ Catch errors retrieving allsky image
	   	if error_status ne 0 then begin
	    	print, 'Error retrieving allsky image'
	    	catch, /cancel
	    	error = 1
	    	return
	   	endif

		;\\ Copy the allsky image from the URL to a local file
		dummy = webget('http://optics.gi.alaska.edu/realtime/latest/pkr_latest_rgb.jpg', $
						copyfile = global.home_dir + 'latest_allsky.jpeg')
	endif
end

pro sdi_monitor_multistatic

	common sdi_monitor_common, global, persistent
	common sdi_monitor_multistatic_common, lastrunId, $ ;\\ to see if we have new data or not
										   lastSaveTime0, $ ;\\ allow low freq. saving of images
										   lastSaveTime1 ;\\ ditto

	if ptr_valid(persistent.zonemaps) eq 0 then return
	if ptr_valid(persistent.snapshots) eq 0 then return
	if size(lastSaveTime0, /type) eq 0 then lastSaveTime0 = systime(/sec) - 1E5
	if size(lastSaveTime1, /type) eq 0 then lastSaveTime1 = systime(/sec) - 1E5

	;\\ Multistatic time-series save file
	saved_data = global.home_dir + '\timeseries\Multistatic_timeseries.idlsave'
	have_saved_data = file_test(saved_data)
	if (have_saved_data eq 1) then restore, saved_data

	base_geom = widget_info(global.tab_id[4], /geometry)
	widget_control, draw_ysize=800, draw_xsize = 600, global.draw_id[4]
	widget_control, get_value = wset_id, global.draw_id[4]

	show_zonemaps = 0
	show_bistatic = 1
	show_tristatic = 1
	show_monostatic = 1
	scale= 5E2

	;\\ UT day range of interest (the current UT day for now, since obs from Alaska don't span days)
		current_ut_day = dt_tm_fromjs(dt_tm_tojs(systime(/ut)), format='doy$')
		ut_day_range = [current_ut_day, current_ut_day]


	;\\ If saved data were restored, slice it so we only have the current ut day
	if have_saved_data eq 1 then begin
		js2ymds, bistatic_vz_times, y, m, d, s
		daynos = ymd2dn(y, m, d)
		slice = where(daynos ge ut_day_range[0] and daynos le ut_day_range[1], nsliced)
		if nsliced eq 0 then begin
			have_saved_data = 0
		endif else begin
			bistatic_vz = bistatic_vz[slice]
			bistatic_vz_times = bistatic_vz_times[slice]
		endelse
	endif

	tseries = file_search(global.home_dir + '\timeseries\*' + $
						  ['HRP','PKR','TLK'] + '*6300*timeseries*', count = nseries)

	for i = 0, nseries - 1 do begin
		restore, tseries[i]

		;\\ Get contiguous data inside ut_day_range
		js2ymds, series.start_time, y, m, d, s
		daynos = ymd2dn(y, m, d)
		slice = where(daynos ge ut_day_range[0] and daynos le ut_day_range[1], nsliced)
		if nsliced eq 0 then continue
		series = series[slice]

		find_contiguous, js2ut(series.start_time) mod 24, 3., blocks, n_blocks=nb, /abs
		ts_0 = blocks[nb-1,0]
		ts_1 = blocks[nb-1,1]
		series = series[ts_0:ts_1]

		append, ptr_new(series), allSeries
		append, ptr_new(meta[0]), allMeta

		append,{dayno:ymd2dn(y[0], m[0], d[0]), $
				js_min:min((series.start_time + series.end_time)/2.), $
				js_max:max((series.start_time + series.end_time)/2.) }, allTimeInfo
	endfor

	nseries = n_elements(allMeta)
	if nseries eq 0 then goto, END_MULTISTATIC

	if nseries gt 0 then begin

		;\\ Find a recent time that all sites can be interpolated to
		common_time = min(allTimeInfo.js_max) - 60.
		js2ymds, common_time, cmn_y, cmn_m, cmn_d, cmn_s

		;\\ Do we have new data, or can we skip this run?
		if (size(lastrunId, /type) ne 0) then begin
			if (lastrunId eq common_time) then goto, END_MULTISTATIC
		endif
		lastrunId = common_time


		allWinds = ptrarr(nseries, /alloc)
		allWindErrs = ptrarr(nseries, /alloc)

		for i = 0, nseries - 1 do begin

				series = (*allSeries[i])
				metadata = (*allMeta[i])
				sdi_monitor_format, {metadata:metadata, series:series}, $
									meta = meta, $
									spek = speks, $
									zone_centers = zcen

				nobs = n_elements(speks)
				if nobs lt 5 then goto, END_MULTISTATIC
				sdi3k_drift_correct, speks, meta, /data_based, /force
				sdi3k_remove_radial_residual, meta, speks, parname='VELOCITY'
	    		speks.velocity *= meta.channels_to_velocity
	    		speks.sigma_velocity *= meta.channels_to_velocity
	    		posarr = speks.velocity
	    		sdi3k_timesmooth_fits,  posarr, 1.1, meta
	    		sdi3k_spacesmooth_fits, posarr, 0.03, meta, zcen
	    		speks.velocity = posarr
	    		speks.velocity -= total(speks[1:nobs-2].velocity[0])/n_elements(speks[1:nobs-2].velocity[0])

				sdi_time_interpol, speks.velocity, $
								   (speks.start_time + speks.end_time)/2., $
								   common_time, $
								   winds

				sdi_time_interpol, speks.sigma_velocity, $
								   (speks.start_time + speks.end_time)/2., $
								   common_time, $
								   wind_errors

				*allMeta[i] = meta
				*allWinds[i] = winds
				*allWindErrs[i] = wind_errors
		endfor
	endif


	altitude = 240.
	n_sites = nseries

	;\\ ######## Bistatic ########
	if nseries ge 2 then begin
		for stn0 = 0, n_sites - 1 do begin
		for stn1 = stn0 + 1, n_sites - 1 do begin

			fit_bistatic, *allMeta[stn0], *allMeta[stn1], $
					  	  *allWinds[stn0], *allWinds[stn1], $
					  	  *allWindErrs[stn0], *allWindErrs[stn1], $
					  	  altitude, $
					  	  fit = fit

			append, fit, bistaticFits
			append, {stn0:(*allMeta[stn0]).site_code, $
					 stn1:(*allMeta[stn1]).site_code }, bistaticPairs

		endfor
		endfor

		;\\ Append the vertical wind data to the multistatic timeseries
		bivz = where(max(bistaticFits.overlap, dim=1) gt .1 and $
					 bistaticFits.obsdot lt .6 and $
					 bistaticFits.mangle lt 3, nbivz)

		if nbivz gt 0 then begin
			save_this_one = 0
			if have_saved_data eq 1 then begin
				if bistatic_vz_times[n_elements(bistatic_vz_times)-1] ne common_time then save_this_one = 1
			endif else begin
				save_this_one = 1
			endelse

			if save_this_one eq 1 then begin
				append, bistaticFits[bivz], bistatic_vz
				append, replicate(common_time, nbivz), bistatic_vz_times
				save, filename = saved_data, bistatic_vz, bistatic_vz_times
			endif
		endif
	endif


	;\\ ######## Tristatic ########
	if nseries ge 3 then begin
		for stn0 = 0, n_sites - 1 do begin
		for stn1 = stn0 + 1, n_sites - 1 do begin
		for stn2 = stn1 + 1, n_sites - 1 do begin

			fit_tristatic, *allMeta[stn0], *allMeta[stn1], *allMeta[stn2], $
					  	   *allWinds[stn0], *allWinds[stn1], *allWinds[stn2], $
					  	   *allWindErrs[stn0], *allWindErrs[stn1], *allWindErrs[stn2], $
					  	   altitude, $
					  	   fit = fit

			append, fit, tristaticFits
			append, {stn0:(*allMeta[stn0]).site_code, $
					 stn1:(*allMeta[stn1]).site_code, $
					 stn2:(*allMeta[stn2]).site_code }, tristaticPairs

		endfor
		endfor
		endfor
	endif


	;\\ Nominal values of middle lat and lon, refined depending on available info
	midLat = 65.
	midLon = -147.
	if size(*global.shared.recent_monostatic_winds, /type) ne 0 then begin
		midLat = mean((*global.shared.recent_monostatic_winds).lat)
		midLon = mean((*global.shared.recent_monostatic_winds).lon)
	endif else begin
		if size(bistaticFits, /type) ne 0 then begin
			midLat = median(bistaticFits.lat)
			midLon = median(bistaticFits.lon)
		endif
	endelse


	wset, wset_id
	tvlct, red, gre, blu, /get
	erase, 0
	plot_simple_map, midLat, midLon, 8, 1, 1, map=map, $
					 backcolor=[0,0], continentcolor=[50,0], $
					 outlinecolor=[90,0], bounds = [0,.25,1,1]

	;\\ Allsky image (only get if sun elevation is below -8 to avoid saturation)
	sdi_monitor_grab_allsky, -8, error=error
	if (error eq 1) or file_test(global.home_dir + '\latest_allsky.jpeg') eq 0 then begin
		allsky_image = fltarr(3,512,512)
	endif else begin
		read_jpeg, global.home_dir + '\latest_allsky.jpeg', allsky_image
	endelse
	plot_allsky_on_map, map, allsky_image, 80., 23, 240., 65.13, -147.48, [600,800], /webimage

	overlay_geomag_contours, map, longitude=10, latitude=5, color=[0, 100]

	if show_zonemaps eq 1 then begin
		for i = 0, nseries - 1 do begin
			plot_zonemap_on_map, 0, 0, 0, 0, 240., $
								 180 + (*allMeta[i]).oval_angle, $
								 0, map, meta=*allMeta[i], front_color = 0, $
								 lineThick=.5, ctable=0
		endfor
	endif


	;\\ Plot small circles around station locations
	loadct, 39, /silent
	for i = 0, nseries - 1 do begin
		xy = map_proj_forward((*allMeta[i]).longitude, (*allMeta[i]).latitude, map=map)
		circ = findgen(361)*!DTOR
		plots, /data, xy[0] + 1.5E4*cos(circ), xy[1] + 1.5E4*sin(circ), thick=1, color = 190
	endfor

	!p.font = 0
	device, set_font='Ariel*17*Bold'


	;\\ Show monostatic winds for context
	if show_monostatic eq 1 then begin
		loadct, 0, /silent
		if size(*global.shared.recent_monostatic_winds, /type) eq 8 then begin

			mono = *global.shared.recent_monostatic_winds
			magnitude = sqrt(mono.geoZonal*mono.geoZonal + mono.geoMerid*mono.geoMerid) * scale
			azimuth = atan(mono.geoZonal, mono.geoMerid) / !DTOR

			;\\ Get an even grid of locations for blending, stay inside monostatic boundary
			missing = -9999
			triangulate, mono.lon, mono.lat, tr, b
			grid_lat = trigrid(mono.lon, mono.lat, mono.lat, tr, missing=missing, nx = 20, ny=20)
			grid_lon = trigrid(mono.lon, mono.lat, mono.lon, tr, missing=missing, nx = 20, ny=20)
			use = where(grid_lon ne missing and grid_lat ne missing, nuse)
			ilats = grid_lat[use]
			ilons = grid_lon[use]

			for locIdx = 0, nuse - 1 do begin

				latDist = (mono.lat - ilats[locIdx])
				lonDist = (mono.lon - ilons[locIdx])
				dist = sqrt(lonDist*lonDist + latDist*latDist)

				sigma = 1.0
				weight = exp(-(dist*dist)/(2*sigma*sigma))
				zonal = total(mono.geoZonal * weight)/total(weight)
				merid = total(mono.geoMerid * weight)/total(weight)

				magnitude = sqrt(zonal*zonal + merid*merid)*scale
				azimuth = atan(zonal, merid) / !DTOR

				get_mapped_vector_components, map, ilats[locIdx], ilons[locIdx], $
										  	  magnitude, azimuth, x0, y0, xlen, ylen

				arrow, x0 - .5*xlen, y0 - .5*ylen, $
					   x0 + .5*xlen, y0 + .5*ylen, /data, color = 100, hsize = 8

			endfor
		endif
		loadct, 39, /silent
	endif



	;\\ Overlay Bistatic Winds
	if show_bistatic eq 1 and size(bistaticFits, /type) ne 0 then begin
		use = where(max(bistaticFits.overlap, dim=1) gt .1 and $
					bistaticFits.obsdot lt .8 and $
					bistaticFits.mangle gt 25 and $
					abs(bistaticFits.mcomp) lt 500 and $
					abs(bistaticFits.lcomp) lt 500 and $
					bistaticFits.merr/bistaticFits.mcomp lt .3 and $
					bistaticFits.lerr/bistaticFits.lcomp lt .3, nuse )

		if (nuse gt 0) then begin
			biFits = bistaticFits[use]

			for i = 0, nuse - 1 do begin

				outWind = project_bistatic_fit(biFits[i], 0)

				magnitude = sqrt(outWind[0]*outWind[0] + outWind[1]*outWind[1]) * scale
				azimuth = atan(outWind[0], outWind[1]) / !DTOR

				get_mapped_vector_components, map, biFits[i].lat, biFits[i].lon, $
											  magnitude, azimuth, x0, y0, xlen, ylen

				arrow, x0 - .5*xlen, y0 - .5*ylen, $
					   x0 + .5*xlen, y0 + .5*ylen, /data, color = 255, hsize = 8

			endfor
		endif

		;\\ Show bistatic vz locations
		if nbivz gt 0 then begin
			order = sort(bistaticFits[bivz].lat)
			xy = map_proj_forward(bistaticFits[bivz[order]].lon, bistaticFits[bivz[order]].lat, map=map)
			xyouts, xy[0,*], xy[1,*], string(indgen(nbivz) + 1, f='(i0)'), align=.5, color = 90, /data
		endif

	endif


	;\\ Scale arrow
	plot_vector_scale_on_map, [.01, .92], map, 200, scale, 0, thick = 2, headthick = 2
	xyouts, .01, .98, 'Bistatic Winds ' + dt_tm_fromjs(dt_tm_tojs(systime(/ut)), format='Y$/doy$'), /normal
	xyouts, .01, .955, time_str_from_decimalut(cmn_s/3600.) + ' UT', /normal
	xyouts, .01, .93, '200 m/s', /normal

	;\\ Explain plotting symbols
	loadct, 0, /silent
	xyouts, .99, .27, 'Mean Monostatic Winds', /normal, color = 100, align=1
	loadct, 39, /silent
	xyouts, .99, .288, 'Station Locations', /normal, color = 190, align=1
	xyouts, .99, .252, 'Bistatic Vertical Wind Locations', /normal, color = 90, align=1


	;\\ Testing vz timeseries
	loadct, 0, /silent
	bi_times = js2ut(bistatic_vz_times)
	times = get_unique(bi_times)
	lats = get_unique(bistatic_vz.lat)

	yrange = [min(bistatic_vz.lat)-.5, max(bistatic_vz.lat)+.5]
	trange = [min(times)-2, max(times)+1]
	if (trange[1] - trange[0]) lt 10 then trange[1] = trange[0] + 10
	scale = 50.

	polyfill, [0,0,1,1], [0,.25,.25,0], color = 0, /normal

	!p.font = -1
	plot, trange, yrange, /nodata, xstyle=9, ystyle=9, ytitle = 'Latitude', xtitle = 'UT TIme', $
		  pos = [.08, .05, .98, .2], /noerase
	!p.font = 0

	;\\ Plot the vertical (base-)lines at each time
	for i = 0, n_elements(lats) - 1 do begin
		oplot, trange, [lats[i],lats[i]], col = 50
	endfor

	device, set_font='Ariel*17*Bold'
	xyouts, .01, .23, 'Bistatic Vertical Wind Timeseries ' + $
				dt_tm_fromjs(dt_tm_tojs(systime(/ut)), format='Y$/doy$'), /normal

	;\\ Plot the vz scale
	device, set_font='Ariel*15*Bold'
	plots, /data, trange[0] + .2 + [1,1], yrange[0] + 2 + [0, 50/scale]
	plots, /data, trange[0] + .2 + [.9,1.1], yrange[0] + 2
	plots, /data, trange[0] + .2 + [.9,1.1], yrange[0] + 2 + [50/scale, 50/scale]
	xyouts, /data, trange[0] + .2 + 1, yrange[0] + 2.2 + 50/scale, '50 m/s', align=.5

	;\\ Indicate location latitudes from the main map
	loadct, 39, /silent
	if show_bistatic eq 1 and size(bistaticFits, /type) ne 0 then begin
		lat = bistaticFits[bivz].lat
		order = sort(lat)
		xyouts, trange[0] + .3 + .15*(indgen(n_elements(order)) mod 2), lat[order], $
				string(indgen(n_elements(order)) + 1, f='(i0)'), /data, color= 90, align=.5


		device, set_font='Ariel*12*Bold'

		for i = 0, n_elements(lats) - 1 do begin
			pts = where(bistatic_vz.lat eq lats[i], npts)
			if npts gt 0 then begin

				vz = bistatic_vz[pts].mcomp
				lat = bistatic_vz[pts].lat
				time = bi_times[pts]
				order = sort(time)

				oplot, time[order], lat[order] + vz[order]/scale, noclip=1
				;xyouts, time[0], yrange[0] - .2, time_str_from_decimalut(time[0], /nosec), /data, align=.5

			endif
		endfor
	endif

	;\\ Save a copy of the image without tristatic
	if 0 then begin ;\\ currently disabled, disk fills up
		if systime(/sec) - lastSaveTime0 gt 15*60. then begin
			datestamp = dt_tm_fromjs(dt_tm_tojs(systime(/ut)), format='Y$0n$0d$')
			timestamp = dt_tm_fromjs(dt_tm_tojs(systime(/ut)), format='h$m$s$')
			toplevel = global.home_dir + '\SavedImages\' + datestamp + '\Multistatic\'
			fname = toplevel + 'Realtime_Multistatic_' + timestamp + '.png'
			file_mkdir, toplevel
			write_png, fname, tvrd(/true)
			lastSaveTime0 = systime(/sec)
		endif
	endif


	;\\ Overlay tristatics last, so we can take a picture with and without...
	;\\ Overlay Tristatic Winds
	if show_tristatic eq 1 and size(tristaticFits, /type) ne 0 then begin
		use = where(max(tristaticFits.overlap, dim=1) gt .2 and $
					tristaticFits.obsdot lt .7 and $
					sqrt(tristaticFits.v*tristaticFits.v + tristaticFits.u*tristaticFits.u) lt 300 and $
					tristaticFits.uerr/tristaticFits.u lt .3 and $
					tristaticFits.verr/tristaticFits.v lt .3, nuse )

		if (nuse gt 0) then begin
			triFits = tristaticFits[use]

			for i = 0, nuse - 1 do begin

				outWind = [triFits[i].u, triFits[i].v]

				magnitude = sqrt(outWind[0]*outWInd[0] + outWind[1]*outWind[1]) * scale
				azimuth = atan(outWind[0], outWind[1]) / !DTOR

				get_mapped_vector_components, map, triFits[i].lat, triFits[i].lon, $
											  magnitude, azimuth, x0, y0, xlen, ylen

				arrow, x0, y0, x0 + xlen, y0 + ylen, /data, color = 150, hsize = 8

			endfor
		endif
	endif

	!p.font = -1

	;\\ Save a copy of the image with tristatic
	if 0 then begin ;\\ currently disabled, disk fills up
		if systime(/sec) - lastSaveTime1 gt 15*60. then begin
			fname = toplevel + 'Realtime_Multistatic_Tri' + timestamp + '.png'
			file_mkdir, toplevel
			write_png, fname, tvrd(/true)
			lastSaveTime1 = systime(/sec)
		endif
	endif


	tvlct, red, gre, blu
	END_MULTISTATIC:
	if (size(allSeries, /type) ne 0) then ptr_free, allSeries, allMeta
end
