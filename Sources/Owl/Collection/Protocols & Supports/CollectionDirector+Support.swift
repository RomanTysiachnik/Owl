//
//  Owl
//  A declarative type-safe framework for building fast and flexible list with Tables & Collections
//
//  Created by Daniele Margutti
//   - Web: https://www.danielemargutti.com
//   - Twitter: https://twitter.com/danielemargutti
//   - Mail: hello@danielemargutti.com
//
//  Copyright © 2019 Daniele Margutti. Licensed under Apache 2.0 License.
//

import UIKit

public extension CollectionDirector {

	/// Define the cell size.
	///
	/// - `default`: standard behaviour (no auto sizing, needs to implement `onGetItemSize` on adapters).
	/// - auto: uses autolayout to calculate the size of the cell. You can provide an
	///				 estimated size of the cell to speed up the calculation.
	///				 Implement preferredLayoutAttributesFitting(_:) method in your cell to evaluate the size.
	/// - explicit: fixed size where each item has the same size
	enum ItemSize {
		case `default`
		case auto(estimated: CGSize)
		case explicit(CGSize)
	}


	// MARK: - Public Supporting Structures -
  
	struct EventsSubscriber {
		typealias HeaderFooterEvent = (view: UICollectionReusableView, path: IndexPath, table: UICollectionView)

		public var layoutDidChange: ((_ old: UICollectionViewLayout, _ new: UICollectionViewLayout) -> UICollectionViewTransitionLayout?)? = nil
    public var targetOffset: ((_ proposedContentOffset: CGPoint) -> CGPoint)? = nil
    public var moveItemPath: ((_ originalIndexPath: IndexPath, _ proposedIndexPath: IndexPath) -> IndexPath)? = nil

		private var _shouldUpdateFocus: ((_ context: AnyObject) -> Bool)? = nil
		@available(iOS 9.0, *)
    public var shouldUpdateFocus: ((_ context: UICollectionViewFocusUpdateContext) -> Bool)? {
			get { return _shouldUpdateFocus }
			set {
        if let shouldUpdateFocus = newValue as? ((AnyObject) -> Bool)? {
          _shouldUpdateFocus = shouldUpdateFocus
        }
      }
		}

		private var _didUpdateFocus: ((_ context: AnyObject, _ coordinator: AnyObject) -> Void)? = nil
		@available(iOS 9.0, *)
    public var didUpdateFocus: ((_ context: UICollectionViewFocusUpdateContext, _ coordinator: UIFocusAnimationCoordinator) -> Void)? {
			get { _didUpdateFocus }
			set {
        if let didUpdateFocus = newValue as? ((AnyObject, AnyObject) -> Void)? {
          _didUpdateFocus = didUpdateFocus
        }
      }
		}
    
    private var _contextMenuPreview: ((_ context: AnyObject) -> AnyObject?)? = nil
    @available(iOS 13.0, *)
    public var contextMenuPreview: ((_ context: UIContextMenuConfiguration) -> UITargetedPreview?)? {
      get { _contextMenuPreview as? ((_ context: UIContextMenuConfiguration) -> UITargetedPreview?)? ?? nil }
      set {
        if let contextMenuPreview = newValue as? ((AnyObject) -> AnyObject?)? {
          _contextMenuPreview = contextMenuPreview
        }
      }
    }
	}

	internal class PrefetchModelsGroup {
		let adapter: 	CollectionCellAdapterProtocol
		var models: 	[ElementRepresentable] = []
		var indexPaths: [IndexPath] = []

		public init(adapter: CollectionCellAdapterProtocol) {
			self.adapter = adapter
		}
	}

}
