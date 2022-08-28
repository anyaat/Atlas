/* exported OfflineMapLayer */
/* global m, AbstractMapLayer */

class OfflineMapLayer extends AbstractMapLayer {

  static STYLE = 'mapbox://styles/sydevadmin/ck7g6nag70rn11io09f45odkq'

  get style() {
    return OfflineMapLayer.STYLE
  }

  constructor(mapbox, config) {
    super(mapbox, Object.assign({
      id: AtlasEvent.LAYER.offline,
      points: {
        'icon-anchor': 'bottom',
        'icon-size': 0.85,
      },
      fetchGeojson: App.data.getGeojson(AtlasEvent.LAYER.offline),
    }, config))
  }

  _gotoLocation(venue) {
    if (venue.eventIds.length > 0) {
      App.data.setCache('venues', venue)
      m.route.set('/venue/:id', { id: venue.id })
    } else {
      m.route.set('/:layer/:id', { id: venue.eventIds[0], layer: AtlasEvent.LAYER.offline })
    }
  }

}
